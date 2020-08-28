---
layout: post
title:  计算机多内核平台上的锁优化(二)
date:   2020-08-21
categories: ["Programming"]
tags: ["Concurrency"]
---

> **申明: 大部分内容来源于网络，我不生产知识，我只是字符串搬运工。**

在[**_Algorithms for scalable synchronization on shared-memory multiprocessors_**](https://www.cs.rice.edu/~johnmc/papers/tocs91.pdf)这篇论文中，CLH锁之前还提到了另外一个锁算法。

## 凭证锁(The Ticket Lock)

这个算法也很形象，比如你去10元快剪理发(假设只有一个理发师)，你得先买票，出票机在出票的时候，会显示前面还有几位在等待，你需要等待多久呢？

假设一个人理发需要10分钟，如果你前面有两人，那么你就要等20分钟。

凭证锁有两个变量，一个表示当前服务的凭证，另外一个是下一个将被服务的凭证。

实现如下:

``` Java
   public class TicketLock {

        private final AtomicLong nextTicket = new AtomicLong(0);
        private final AtomicLong nowServing = new AtomicLong(0);

        public void lock() {
            long myTicket = nextTicket.getAndIncrement();
            while (true) {
                //只为了表达算法，没catch异常
                Thread.sleep(myTicket - nowServing.get());
                if (nowServing.get() == myTicket) {
                    return;
                }
            }
        }

        public void unlock() {
            nowServing.incrementAndGet();
        }
    }
```
凭证锁在test_and_set锁的基础上，其实也是做到了FIFO的公平性，而且不会有饥饿的情况。

凭证锁相当于用事件计数和序号实现的信号量。

这种锁的缺点也很明显，需要循环读取nowServing变量，在多核CPU多级缓存架构下，同时读取共享变量，会带来大量的内存和带宽竞争，虽然sleep降低了内核之间的连续竞争,但随着获取锁的内核数量增加，会导致Exponential backoff。

>"Exponential backoff is an algorithm that uses feedback to multiplicatively decrease the rate of some process, in order to gradually find an acceptable rate"

很可能发生，当上一个内核已经从临界区退出并释放了锁，但其他的内核还在sleep。

即便用固定的sleep时间也不合理，因为临界区执行的时间是未知的。

另外一个细节就是，这个算法是建立在假设`nextTicket.getAndIncrement()`不会溢出的情况下。

在`The Ticket Lock`之后还有`Array-Based Queuing Locks`，但由于基于数组的队列锁，性能更不理想，所以就略过了。

在`Array-Based Queuing Locks`之后就是 `List-Based Queuing Lock `，[*计算机多内核平台上的并发锁优化(一)*](https://blog.xiebiao.com/post/2020-08-19-locks-on-multicore/)中讲到的CLH锁和MCS锁都是基于链表队列实现的。

## 栅栏(BARRIERS)
首先对`Barrier`这个中文翻译解释一下，实际上[朗文词典对该词给出的英文翻译如下](https://www.ldoceonline.com/dictionary/barrier)：

- 1、a rule, problem etc that prevents people from doing something, or limits what they can do
- 2、a type of fence or gate that prevents people from moving in a particular direction
- 3、a physical object that keeps two areas, people etc apart

很多中文书籍用的是2条翻译，实际上第1条翻译才是在计算机领域中要表达的含义。

这个对应现实生活中的例子就是，你和几个好友约定晚上7点去苍蝇馆子撸串，说好了人不齐不许开干，那么先到的只能看着烤串流口水。

规则就这么简单。

未完待续......

## 相关阅读

- [*计算机多内核平台上的并发锁优化(一)*](https://blog.xiebiao.com/post/2020-08-19-locks-on-multicore/)
- [*The ccNUMA Memory Profiler*](http://www.cs.utah.edu/~ald/pubs/CC-numa.pdf)
- [*Overview of Recent Supercomputers*](http://www.netlib.org/utk/papers/advanced-computers/overview.html)
- [*A Hierarchical CLH Queue Lock*](https://people.csail.mit.edu/shanir/publications/CLH.pdf)
- [*A General Technique for Designing NUMA Locks*](http://groups.csail.mit.edu/mag/a13-dice.pdf)