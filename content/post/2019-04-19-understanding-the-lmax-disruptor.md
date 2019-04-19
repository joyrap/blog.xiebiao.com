---
layout: post
title:  翻译:Understanding the LMAX Disruptor
date:   2019-04-18 18:24:47
categories: ["Translate","Programming"]
tags: ["Disruptor"]
---

### 翻译前言

知道Disruptor这个工具包，是在Log4j 1.X升级版Log4j2中提到的，那时候就好奇它为何如此高效，
关于Disruptor的文章在[ifeve.com](http://ifeve.com/disruptor/)上已经有很多了，这一篇讲的更简单。
由于个人英文水平有限，更多是意译。

-----------------

[LMAX Disruptor](https://github.com/LMAX-Exchange/disruptor) 是由一家金融交易平台公司[LMAX Exchange](https://www.lmax.com/)开源的Java包,它极其优雅，高效地解决了线程间的通信。

在这篇博文中，我先描述关于传统排队系统在跨线程之间的内存共享问题，然后，试图弄清楚LAMX Disruptor 在该问题上有什么特别方案，他们是如何做到的。

![understanding-the-lmax-disruptor](http://blog.xiebiao.com/images/2019-04-19-understanding-the-lmax-disruptor/1_faUySbv7t8aAFm0X1zTMwg.png "")

- LMAX Disuptor 的解决方案比`ArrayBlockingQueue`和`LinkedBlockingQueue`要快。
- 更好的理解底层硬件可以让成为更好的开发人员。
- 在线程中共享内存很容易引发问题，需要小心。
- CPU缓存比主存更快，但是不懂他们是如何工作的(行缓存，等等)反而会严重影响性能。

### 共享内存的陷阱

举个例子，我们需要对一个计数器循环递增到`MAX`:

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

首先,多次执行将`MAX`累加到1百万，显然我们期望输出`counter=1000000`,会是这样吗？

```
counter=522388
counter=733903
counter=532331

```
由于变量 `sharedCounter`上的条件竞争，执行结果出现了不确定性。

条件竞争发生在当一个结果依赖进程/线程的执行顺序和执行时间。
这种场景下，是因为`sharedCounter`在没有被保护的情况下，同时被两个线程修改。

其次，关于性能，即使忽略两个线程对值很大的`MAX`的管理，这个结果依然要慢3倍多。这是什么原因？

由于两个线程属于CPU计算密集型，操作系统很有可能会将他们分配到不同的CPU内核上，另外，我们有理由相信
两个运行在不同内核上的线程可以自由共享内存，然而，我们忘了CPU缓存的概念:

![understanding-the-lmax-disruptor](http://blog.xiebiao.com/images/2019-04-19-understanding-the-lmax-disruptor/1_I_7Ju4oDPgTYO6Y-uPqdQg.png "Memory layers")

为了避免每次都访问主存中查询内存地址，CPU会将缓存数据保存在自己的缓存中: 本地一级缓存，二级缓存，和共享三级缓存。

[Core i7 Xeon 5500](https://software.intel.com/sites/products/collateral/hpc/vtune/performance_analysis_guide.pdf)的特性:

| Memory   |      Latency      |  
|----------|:-------------:|
| L1 CACHE hit |  ~4 cycles (~1.2 ns) | 
| L2 CACHE hit |    ~10 cycles (~3.0 ns)   |   
| L3 CACHE hit | (~60.0 ns) |   

当处理器想访问一个内存地址，首先会在一级缓存中查找，如果不存在，再从二级缓存中查找，同样如果不存在就到三级缓存中查找，
直到最后到主存中查找(主存比一级缓存慢60倍)。

在我们的例子中，因为`sharedCounter` 同时被两个不同的CPU内核更新，变量在两个一级缓存中来回同步，大幅度降低了执行速度。

最后，这里有另外一个重要关于CPU缓存的概念: 行缓存



>原文地址:[https://itnext.io/understanding-the-lmax-disruptor-caaaa2721496](https://itnext.io/understanding-the-lmax-disruptor-caaaa2721496)

------

### 翻译后记

很早以前发现使用英译中工具查单词，有个严重的误区，比如`ruin`这个单词，百度翻译/有道翻译/google翻译基本都是告诉你中文意思为：`毁灭；使破产`。
但是用[朗文翻译](https://www.ldoceonline.com/dictionary/ruin)得到的英文解释为: `to spoil or destroy something completely`,这个解释里面明显有个`程度`在里面，
如果翻译成`毁灭`也显得生硬，影响理解。

