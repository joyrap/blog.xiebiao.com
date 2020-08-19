---
layout: post
title:  多内核平台上的锁
date:   2020-08-19
categories: ["Programming"]
tags: ["Concurrency"]
---
如何在高并发的情况下，提高多核CPU的性能，一直是在并发编程领域中非常重要的问题。
特别是随着云厂商按计算收费的当下，如何有效地利用资源变得更重要。

> 致富的途径只有两种：一种是拼命赚钱，另外一种就是节约花钱。

## 什么是锁
在计算机硬件层是没有`锁`这个概念的，计算机领域中操作系统的`锁`来源于现实生活中的锁，它的作用是保护某种资源同一时间不能被多人访问。现代计算机都是多核CPU处理器，我们需要通过锁机制来协调多个内核对资源的访问操作。

和现实中一样，在给资源上锁的时候，我们可能需要几个步骤：
1. 拿出钥匙
2. 锁上资源
3. 解锁

计算机中对应的CPU操作就是执行几条指令(CPU每条执行指令都是原子级别的操作，要么成功，要么失败，这是二进制世界的规则)。

这里罗列几条与后面要讲到的锁相关的硬件同步汇编指令

- test_and_set
- swap
- get_and_add
  
**test_and_set** 由3条CPU原语组成
``` c
​    boolean test_and_set(*lock){
​       boolean old=*lock;
​       *lock=true;
​       return old;
    }

```
BTS 的指令含义是在执行 BT 命令的同时, 把操作数的指定位置为 1
``` c
  do{
       //当*lock为false是跳出该循环
       while(test_and_set(*lock));
       critical section;//访问临界区
      *lock=false;
}while(true)
```
**swap**也是由三条CPU原语组成:
BSWAP的指令含义是：把32/64位寄存器的值按照低和高的字节交换(下面代码实现其实就是0=false,1=true交换)
``` c
void swap(boolean *a,boolean *b){
    boolean temp=*a;
    *a=*b;
    *b=temp;
}
do{
    key=true;
    do{
    swap(&lock,&key);
    }while(key)
    //上面初值为false
    cirtical section//访问临界资源
    lock=false;
}while(true)
```
上面简要地说明了通过CPU硬件同步原语，对某个内存地址标志位的修改，起到加锁的作用。

那么锁机制和性能有什么关系呢？这得从CPU缓存说起，因为你要加的锁在CPU缓存中。

## 多核CPU多级缓存架构

早期的CPU架构基本上都采用SMP(Symmetric Multi-Processor)，这种对称多处理器结构，多个CPU内核共享内存资源，除了内存速度访问慢以外，
还可能导致访问冲突。

现代CPU为了提高数据的访问速度，采用了NUMA(Non-Uniform Memory Access)多级缓存的架构，如下图:

![CPU多级缓存](http://blog.xiebiao.com/images/2020-08-19-locks-on-multicore/CPU_Cache.png "")

由于内存读取速度的较慢(科技发展遇到了阻碍?)，但是CPU读取速度提升较快，所以CPU厂商就在内存和CPU之间加了多级缓存来提高性能。

![访问速度与容量对比](http://blog.xiebiao.com/images/2020-08-19-locks-on-multicore/CPU_Cache.png "图片来源于网络，请联系删除")

内核首先从L1缓存中读取数据，如果没有就到L2缓存中读取，如果没有就到
L3缓存中去读取，最坏的情况就是L3缓存也没有，那就只能到内存中去读取。

但这种方案也不是没有弊端，因为越是靠近内核的缓存越贵，不能肆意地设计得很大。

更详细的内存架构介绍，建议阅读:[圖解RAM結構與原理，系統記憶體的Channel、Chip與Bank](https://www.techbang.com/posts/18381-from-the-channel-to-address-computer-main-memory-structures-to-understand?page=2)

## 自旋锁

上面介绍了CPU多级内存架构，有助于理解后面锁相关的性能问题。同时上面还提到了一种硬件同步锁实现**test_and_set**，从实现中你可能发现代码中使用了:
``` c
while(test_and_set(*lock));
```
这就是自旋锁，自旋锁的原理是，如果锁被别的执行单元保持，那么调用者就一直循环在那里查看锁保持者是否释放了锁，即忙则等待。

这里有个细节就是等待的调用者并不是休眠，而是一直在工作占用CPU。

结合上面提到的多核多级CPU缓存，如果当多个内核执行单元都在调用获取锁时，没有获取到锁的内核将一直繁忙，处于中断状态。

所以这种自旋锁的缺点就是:
1. 容易导致死锁
2. 过度消耗CPU资源
3. 竞争不具备公平性
   
对于第3点，很容易想到，如果执行单元释放了锁，后面哪个执行单元会获取到锁呢？这里没有机制保证每个执行单元都能获取到锁。

### CLH锁

基于上面说的缺点，计算机界的大拿总有解决办法的，于是就有了1991年提出的这篇论文[*Algorithms for scalable synchronization on shared-memory multiprocessors*](https://dl.acm.org/doi/10.1145/103727.103729)，这篇论文中提出了CLH锁(Craig, Landin, and Hagersten  locks): 也是一个自旋锁。

CLH锁解决了饥饿问题，通过FIFO来保证公平性。

CLH锁也是一种基于链表的可扩展、高性能、公平的自旋锁，申请线程只在本地变量上自旋，它不断轮询前驱的状态，如果发现前驱释放了锁就结束自旋。

CLH锁的实现如下:

1. 两个ThreadLocal变量，一个表示当前节点，一个表示前趋节点
2. 通过CAS原语加入队尾
3. 每个线程尝试用自己去替换tail，并循环获取前趋节点上的锁，直到锁被释放。
4. 线程释放锁之后，将当前节点设置为前继节点

``` Java
public class CLHLock {
    private final ThreadLocal<QNode> prev; 
    private final ThreadLocal<QNode> current; 
    private final AtomicReference<QNode> tail = new AtomicReference<QNode>(new QNode());

    public CLHLock() {
        this.prev = new ThreadLocal<QNode>() {
            @Override
            protected QNode initialValue() {
                return null;
            }
        };
        this.current = new ThreadLocal<QNode>() {
            @Override
            protected QNode initialValue() {
                return new QNode();//线程本地本地缓存
            }
        };
    }

    public void lock() {
        QNode current = this.current.get(); 
        current.lock = true;
        QNode pred = this.tail.getAndSet(current); 
        this.prev.set(pred); 
        while (pred.lock) ;//自旋
    }

    public void unlock() {
        QNode current = this.current.get();
        current.lock = false;
        this.current.set(this.prev.get());
        current = null;//GC
    }

    private static class QNode {
        private volatile boolean lock = false;
    }
}
```

CLH自旋锁的优点是空间复杂度低，L个线程n个锁的复杂度为O（L+n）

JAVA并发框架中(`java.util.concurrent.locks.AbstractQueuedSynchronizer.Node`)也是基于CLH锁。

``` JAVA
    /**
     * Wait queue node class.
     *
     * <p>The wait queue is a variant of a "CLH" (Craig, Landin, and
     * Hagersten) lock queue. CLH locks are normally used for
     * spinlocks.  We instead use them for blocking synchronizers, but
     * use the same basic tactic of holding some of the control
     * information about a thread in the predecessor of its node.  A
     * "status" field in each node keeps track of whether a thread
     * should block.  A node is signalled when its predecessor
     * releases.  Each node of the queue otherwise serves as a
     * specific-notification-style monitor holding a single waiting
     * thread. The status field does NOT control whether threads are
     * granted locks etc though.  A thread may try to acquire if it is
     * first in the queue. But being first does not guarantee success;
     * it only gives the right to contend.  So the currently released
     * contender thread may need to rewait.
```

如果你对上面讲的多核CPU多级缓存架构还有印象，那么你还是会发现CLH锁也有一个明显的缺点，
那就是:

``` Java
  while (pred.lock) ;//自旋
```
这里的自旋可能发生在非本地缓存上，那么当内核需要循环读取一个非本地(或者说离自己很远)缓存中的数据时，在多级缓存架构中那就是个灾难。

于是就有了......

### MCS锁

MCS锁对CLH锁进行了优化，自旋发生在本地节点上。

实现如下:
1. 队列初始化时没有结点，tail=null
2. 线程A想要获取锁，于是将自己置于队尾，由于它是第一个结点，它的locked域为false
3. 线程B和C相继加入队列，a->next=b,b->next=c。且B和C现在没有获取锁，处于等待状态，所以它们的locked域为true，
尾指针指向线程C对应的结点
4. 线程A释放锁后，顺着它的next指针找到了线程B，并把B的locked域设置为false。这一动作会触发线程B获取锁

``` Java
public class MCSLock  {
    private AtomicReference<QNode> tail;
    private ThreadLocal<QNode> current;

    @Override
    public void lock() {
        tail = new AtomicReference<QNode>(new QNode());  
        QNode current = this.current.get();
        QNode pred = tail.getAndSet(current);
        if (pred != null) {
            current.locked = true;
            pred.next = current;
            while (current.locked) ;//自旋
        }
    }

    @Override
    public void unlock() {
        QNode current = this.current.get();
        if (current.next == null) {
            if (tail.compareAndSet(current, null)){
                return;
            }
            while (current.next == null) ;//自旋
        }
        current.next.locked = false;
        current.next = null;
    }

    private static class QNode {
       volatile boolean locked = false;
        QNode next = null;
    }
}
```


## 参考

[*Locks on Multicore and Multisocket Platforms*](http://https://www.cs.rice.edu/~johnmc/comp522/lecture-notes/COMP522-2019-LocksOnMulticore.pdf)

[https://www.cnblogs.com/yuyutianxia/p/4296220.html](https://www.cnblogs.com/yuyutianxia/p/4296220.html)
