---
layout: post
title:  翻译:Understanding the LMAX Disruptor
date:   2019-04-19 21:24:47
categories: ["Translate","Programming"]
tags: ["Disruptor"]
---

### 翻译前言

知道Disruptor这个代码库，是在Log4j 1.X升级版Log4j2中提到的，那时候就好奇它为何如此高效，关于Disruptor的文章在[ifeve.com](http://ifeve.com/disruptor/)上已经有很多了，这一篇讲的更简单。

由于个人英文水平有限，更多是意译。

---

[LMAX Disruptor](https://github.com/LMAX-Exchange/disruptor) 是由一家金融交易平台公司[LMAX Exchange](https://www.lmax.com/)开源的Java包,它为线程间的通信问题提供了极其优雅，高效的解决方案。

在这篇博文中，我先描述关于传统排队系统在跨线程之间的内存共享问题，然后试图弄清楚LAMX Disruptor 在该问题上有什么特别方案，他们是如何做到的。

![understanding-the-lmax-disruptor](http://blog.xiebiao.com/images/2019-04-19-understanding-the-lmax-disruptor/1_faUySbv7t8aAFm0X1zTMwg.png "")

- LMAX Disuptor 的解决方案比`ArrayBlockingQueue`和`LinkedBlockingQueue`要快。
- [Mechanical sympathy](http://mechanical-sympathy.blogspot.com/)让你成为更好的开发人员。(更好地理解底层硬件) 
- 在线程中共享内存很容易引发问题，你需要小心对待。
- CPU缓存比主存更快，但是不懂得他们是如何工作的(行缓存，等等)反而会严重影响性能。

### 内存伪共享

举个例子，我们需要对一个计数循环递增到`MAX`:

```
public void simple() {
  int counter = 0;
  for (int i = 0; i < MAX; i++) {
    counter++;
  }
  
  System.out.println("counter=" + counter);
}

```

因为`MAX`值可能会很大，为了关注性能，我们决定在多核处理器上来跑这个程序，将这个任务分到两个独立的线程上执行，像这样:

```
public void multi() throws Exception {
  // First thread
  final Thread t1 =
      new Thread(() -> {
        for (int i = 0; i < MAX / 2; i++) {
          sharedCounter++;
        }
      });

  // Second thread
  final Thread t2 =
      new Thread(() -> {
        for (int i = 0; i < MAX / 2; i++) {
          sharedCounter++;
        }
      });

  // Start threads
  t1.start();
  t2.start();

  // Wait threads
  t1.join();
  t2.join();

  System.out.println("counter=" + sharedCounter);
}

```

可是这个实现有两个问题。

首先,多次执行将`MAX`累加到1百万，很显然这和我们期望输出结果`counter=1000000`有点不一样。(这里完全是个人为了句子更符合中文语景)

```
counter=522388
counter=733903
counter=532331

```
由于变量 `sharedCounter`上的条件竞争，执行结果出现了不确定性。

当线程执行依赖执行顺序和时间，那么就会产生竞态。发生这种情况，是因为`sharedCounter`在没有被保护的情况下，同时被两个线程修改。

其次，至于性能，即使`MAX`被设置成一个很大的值足以忽略两个线程的管理，这个结果依然要慢3倍(文章这里应该是在和单线程下执行结果做比较)。这是什么原因？

由于两个线程属于CPU计算密集型，操作系统很有可能会将他们分配到不同的CPU内核上，另外，我们有理由相信
两个运行在不同内核上的线程可以自由共享内存，然而，我们忘了CPU缓存的概念:

![understanding-the-lmax-disruptor](http://blog.xiebiao.com/images/2019-04-19-understanding-the-lmax-disruptor/1_I_7Ju4oDPgTYO6Y-uPqdQg.png "Memory layers")

为了避免每次都访问主存中查询内存地址，CPU会将数据保存在自己的缓存中: 本地一级缓存，二级缓存，和共享三级缓存。

[Core i7 Xeon 5500](https://software.intel.com/sites/products/collateral/hpc/vtune/performance_analysis_guide.pdf)的特性:

```
Memory                   Latency      
L1 CACHE hit         ~4 cycles (~1.2 ns) | 
L2 CACHE hit         ~10 cycles (~3.0 ns)   |   
L3 CACHE hit          (~60.0 ns) |   

```

当处理器想访问一个内存地址，首先会在一级缓存中查找，如果不存在，再从二级缓存中查找，同样如果不存在就到三级缓存中查找，
直到最后到主存中查找。(主存比一级缓存慢60倍，一级缓存和二级缓存是CPU内核独占，三级缓存是所有CPU内核共享)

在我们的例子中，因为`sharedCounter` 同时被两个不同的CPU内核更新，变量在两个一级缓存中来回同步，大幅度降低了执行速度。

最后，这里有另外一个关于CPU缓存的重要概念: CPU缓存行(CPU缓存的组织形式)

一个缓存行是由2的N次方的连续字节组成，常见的是64字节，它由一个非链式的HashMap维护，每个内存地址都影射到指定的缓存行上。

举例,如果两个变量`x`和`y` 被两个不同的CPU内核的线程顺序访问，第一个线程修改`x`，另外一个在很短时间内修改了`y`(原文为啥要精确到纳秒来阐述?)。
假设两个变量都在同一个缓存行，即使程序只关心变量`y`而不是`x`,第二线程依然会看到整个缓存行被设置成了`无效`，从而导致第二个内核需要重新获得一份缓存行的拷贝(他们可能在2级或者3级缓存，甚至在主存中)。

这个问题就是所谓的`伪共享`,它是影响性能的重要因素(尽管CPU最终会保证执行结果的确定性)。

### 并发执行

代码并发执行首先要确保`相互排斥`,这意味着多线程访问相同的资源需要互相协作。

此外，当发生修改，必须对另外的线程可见，这叫着`修改可见性`

这是并发的两个主要概念。

### 互相排斥

`锁`是实现排斥的一种可能解决方案，但是他们在竞争中公平仲裁显得非常昂贵。操作系统在线程等待锁直到释放之前将其挂起，从而形成上下文
切换。

而且，在上下文切换的过程中(当操作系统释放控制，决定去执行其他任务也一样)，执行上下文可能会丢失之前的缓存和指令。

为了理解其中的影响，我们看看在一个64位计数上循环执行递增500万次:

```
Test case                            Execution time
Single thread                             300ms
Single thread with lock             10 000 ms
Two thread with lock                 224 000ms

```

`锁`的另外一种替代方案就是 `CAS`(比较后交换)操作，`CAS`操作是一个机器指令，它保证操作的原子性(要么全部成功，要么都不成功)。

简而言之，只有传入期望参数与原来值相等时，才会将变量更新，否则让线程继续重试`CAS`操作。

```
   public final int getAndSet(int newValue) {
        for (;;) {
            int current = get();//当前线程获取变量原来的值
            //当current与原来的值相等时，才将变量更新为newValue,因为get到的current，
            //可能已经被另外的线程更新了。
            if (compareAndSet(current, newValue))
                return current;
        }
    }

```
在Java中，`Atomic*` 类，比如`AtomicInteger` 都是基于这种操作。

我们比较一下性能:

```
Test case                                      Execution time
Single thread with CAS                           5 700 ms
Two threads with CAS                             30 000 ms
```

最后不能不提，如果临界区(被保护的部分)不是单个原子操作，需要多个`CAS`操作组合，那将会是更复杂处理方式。

### 修改可见性

修改可见性可以通过`内存屏障`来做到。(也叫内存栅栏)

> A memory barrier causes a CPU to enforce an ordering constraint on memory operations issued before and after the barrier instruction.

> Source: Wikipedia

> 内存屏障会引起CPU在屏障前后对内存操作指令进行重排。

我们为什么需要这种机制？大部分现代CPU为了达到最佳性能最终可能会乱序执行。

回到我们第一个例子:

```
public void simple() {
  int counter = 0;
  for (int i = 0; i < MAX; i++) {
    counter++;
  }
  System.out.println("counter=" + counter);
}

```
这个例子，不管在循环体内`counter`是否被更新，为了执行性能CPU都会进行`指令重排`。

重排在单线程执行中不会有任何问题，但在并发执行上下文中可能会变得不可预知。

这就是`内存屏障`目的:

- 确保多核CPU情况下，临界区被所有指令有序访问。
- 让内存在底层缓存间保持可见。

`内存屏障`被分为以下几种类型:(以下内容和原文不太一致)

> - LoadLoad屏障：对于这样的语句Load1; LoadLoad; Load2，在Load2及后续读取操作要读取的数据被访问前，保证Load1要读取的数据被读取完毕。
> - StoreStore屏障：对于这样的语句Store1; StoreStore; Store2，在Store2及后续写入操作执行前，保证Store1的写入操作对其它处理器可见。
> - LoadStore屏障：对于这样的语句Load1; LoadStore; Store2，在Store2及后续写入操作被刷出前，保证Load1要读取的数据被读取完毕。
> - StoreLoad屏障：对于这样的语句Store1; StoreLoad; Load2，在Load2及后续所有读取操作执行前，保证Store1的写入对所有处理器可见。它的开销是四种屏障中最大的。 在大多数处理器的实现中，这个屏障是个万能屏障，兼具其它三种内存屏障的功能。


![understanding-the-lmax-disruptor](http://blog.xiebiao.com/images/2019-04-19-understanding-the-lmax-disruptor/1_fPGrtZi8xjULvcvoG4jbRw.jpeg " ")


在Java中，使用`volatile`修饰符来插入一个写屏障指令在我们写之后，在读之前插入一个读屏障，同时`final`修饰的类
在其构造完成后插入一个写屏障来使其可见。

可以通过`Unsafe`包来访问这些指令。

我们修改一下之前的多线程实现，在访问`sharedCounter`之前插入一个读屏障，在期后面插入一个写屏障:

```
public void barrier() throws Exception {
  // First thread
  final Thread t1 =
      new Thread(() -> {
        for (int i = 0; i < MAX / 2; i++) {
          getUnsafe().loadFence(); // Read barrier
          sharedCounter++;
          getUnsafe().storeFence(); // Store barrier
        }
      });

  // Second thread
  final Thread t2 =
      new Thread(() -> {
        for (int i = 0; i < MAX / 2; i++) {
          getUnsafe().loadFence(); // Read barrier
          sharedCounter++;
          getUnsafe().storeFence(); // Store barrier
        }
      });

  // Start threads
  t1.start();
  t2.start();

  // Wait threads
  t1.join();
  t2.join();

  System.out.println("counter=" + sharedCounter);
}

```
我们再次运行这个实现 直到`MAX` 到1百万，我们依然期望得到输出  `counter = 1000000`:

```
-- First multi-threaded implementation without a memory barrier
counter=522388
counter=733903
counter=532331
-- New implementation with memory barriers
counter=999890
counter=999868
counter=999770

```

像我们看到的那样，由于内存屏障的介入，结果已经非常接近我们的预期了，然而，即使内存屏障也不足以阻止非原子操作的条件竞争。

### 传统队列

![understanding-the-lmax-disruptor](http://blog.xiebiao.com/images/2019-04-19-understanding-the-lmax-disruptor/1_pX-zOhchRgU7jJKTVtW9dw.jpeg " ")

线程间内存共享另外一个选择就是消息传递: 通过通讯来共享内存。

那意味着我们需要一些东西来处理线程间的通讯，在Java中，一种选择就是使用传统的`LinkedBlockingQueue`或者`ArrayBlockingQueue`。

即使队列能确保互斥和修改可见性但依然不能解决并发问题。

我们看一下 `ArrayBlockingQueue` 的 `put`方法:

```
/** Main lock guarding all access */
final ReentrantLock lock;

public void put(E e) throws InterruptedException {
    checkNotNull(e);
    final ReentrantLock lock = this.lock;
    lock.lockInterruptibly(); // Lock accesses
    try {
        while (count == items.length)
            notFull.await();
        enqueue(e); // See method below
    } finally {
        lock.unlock(); // Unlock
    }
}

private void enqueue(E x) {
    final Object[] items = this.items;
    items[putIndex] = x;
    if (++putIndex == items.length)
        putIndex = 0;
    count++;
    notEmpty.signal(); // Send signal to indicate a change
}

```
在一个锁操作中，当一个元素被添加时会给等待线程发送一个信号。

LMAX 小组觉得有趣的是，队列在满载和为空的情况下总是处于关闭状态。(当队列满了的时候，生产者无法再向队列写入，处于等待状态，当
队列为空时，消费者无法从队列中获取，处于等待状态)

如果队列处于满载而无法写入，结果生产者之间出现竞争，以至于导致上下文切换，缓存数据和指令丢失。

而且，传统的队列系统，生产者操作队头的同时消费者操作队尾。如果队列为空，很可能队头，队尾，以及队列的容量都在同一个`缓存行`中，这将导致上面说的伪共享。

### LMAX Disruptor

![understanding-the-lmax-disruptor](http://blog.xiebiao.com/images/2019-04-19-understanding-the-lmax-disruptor/1_q5N4j_PrALLLpZLEU3c5FA.jpeg " ")

LMAX Disruptor的缔造者发明的[Mechanical Sympathy](https://www.infoq.com/presentations/mechanical-sympathy)也非常著名，
简而言之，开发人员在设计算法，数据结构时要懂得底层硬件。基于这个哲学，该团队才创造这个伟大的代码库。

> Disruptor 显著的降低了写竞争，更低的并发负载，缓存更加友好，实现了高吞吐量，低延迟。

> 来源:[Disruptor technical paper](https://lmax-exchange.github.io/disruptor/files/Disruptor-1.0.pdf)

我们分析一下原因:

首先,Disruptor基于 [ring buffer structure](https://en.wikipedia.org/wiki/Circular_buffer), 它就像一个个固定长度的缓存区首尾相连。


![understanding-the-lmax-disruptor](http://blog.xiebiao.com/images/2019-04-19-understanding-the-lmax-disruptor/1_soxodeCvj-FY8vrl_WY6kA.png "Ring buffer structure")

初始化时，分配指定的内存大小(必须是2的N次方)，以及一个事件初始化工厂。

```
Disruptor<MyEvent> disruptor =
  new Disruptor<>(
      () -> new MyEvent(), // Factory for events
      ringBufferSize, // Buffer size
      threadFactory, 
      producerType, 
      waitStrategy);
    
```

这里启动的时候，我们分配了一个`ringBufferSize`大小的 `MyEvent`类实例。

同时我们提供了一个工厂来创建事件处理器线程，以及一个降低订阅者的策略。我们稍微在后面再讨论生产者。

事件实例在Disruptor中将会被重复利用，相比传统的队列会被垃圾回收器处理，事件会存活更长时间。

在内部， ring buffer支持对象数组，据创造者说这是一个很好的选择。在硬件层级，数组有一个可预知的访问模式，
元素可以预加载，所以事件处理器不用频繁的回到主存中加载下一个元素。这样，我们就可以高效地遍历，而不像队列
那样通过链表的方式访问。

可以像这样配置一个消费者:

```

disruptor.handleEventsWith(
        (event, sequence, endOfBatch) -> System.out.println(event));

```

对`handleEventsWith()`我们提供lambda表达式, lambda有三个输入:

- 事件本身
- 一个序列号
- 是否批量处理

多生产者的情况下，他们都会收到每个事件，如果我们像分开加载，我们可以实现基于序列号的分片策略，像这样:

```
disruptor.handleEventsWith(
    (event, sequence, endOfBatch) -> {
      if (sequence % 2 == 0) {
        System.out.println("Consumer 1: " + event.getPayload());
      }
    },
    (event, sequence, endOfBatch) -> {
      if (sequence % 2 == 1) {
        System.out.println("Consumer 2: " + event.getPayload());
      }
    }
);
```

然后我们可以启动 Disruptor，返回一个`RingBuffer`实例。

```
RingBuffer<MyEvent> ringBuffer = disruptor.start();
```
当`Disruptor`实例被启动，我们就可以通过下面这样发布事件:

```
final long sequence = ringBuffer.next(); // Ask the ring buffer the next sequence
final MyEvent event = ringBuffer.get(sequence); // Get the event instance
event.setPayload("Hello, World!"); // Business logic
ringBuffer.publish(sequence); // Publish an event

```
序列号表示事件在ring buffer数据结构中的位置。

当我们创建`Disruptor`实例，我们同时要传入一个`producerType`变量(它是`ProducerType.SINGLE`或`ProducerType.MULTI`之一)。告诉`Disruptor`我们是否有单个还是多个生产者。

在单个生产者的情况下，`ringBuffer.next()`完全是一个无锁操作。另外一方面，如果我们有多个生产者，这个方法通过`CAS`操作从ring buffer中获取下一个序列号。

序列号通过内存补全的方式确保在同一个缓存行中不包含其他数据:

```
class LhsPadding {
    protected long p1, p2, p3, p4, p5, p6, p7;
}

class Value extends LhsPadding {
    protected volatile long value;
}

class RhsPadding extends Value {
    protected long p9, p10, p11, p12, p13, p14, p15;
}
```
而且，通过创建一个内存屏障，确保所有缓存得到发布事件的更新。在ring buffer中添加一个事件完全不需要锁，从而性能得到了大大提升。

最后一点需要提到的，我们说ring buffer底层是一个数组，那意味着，开发人员阻止了同缓存行中的可能出现的伪共享问题。

我们看看Disruptor开发小组对Disruptor与`ArrayBlockingQueue`比较。

测试中的吞吐性能ops/sec(P表示生产者，C表示消费者)

  ***性能测试数据对比这里就不翻译了***

>  原文地址: [https://itnext.io/understanding-the-lmax-disruptor-caaaa2721496](https://itnext.io/understanding-the-lmax-disruptor-caaaa2721496) 

------

### 扩展阅读

* [perfbook](https://mirrors.edge.kernel.org/pub/linux/kernel/people/paulmck/perfbook/perfbook.html)


### 翻译后记

#### 关于翻译
很早以前发现使用英译中工具查单词，有个严重的误区，比如`ruin`这个单词，百度翻译/有道翻译/google翻译基本都是告诉你中文意思为：`毁灭；使破产`。
但是用[朗文翻译](https://www.ldoceonline.com/dictionary/ruin)得到的英文解释为: `to spoil or destroy something completely`,这个解释里面明显有个`程度`在里面，
如果翻译成`毁灭`就显得生硬，影响理解。



