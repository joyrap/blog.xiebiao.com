---
layout: post
title:  Clojure中的数据类型
date:   2019-11-19
categories: ["Programming"]
tags: ["Clojure"]
---

[Clojure](http://clojure.org)作为一款基于JVM的LISP语言，我个人从创造者[Rich Hickey](https://twitter.com/richhickey)身上吸收了很多编程的观点，尽管作者提出了很多面向对象编程语言的缺陷，但单从语言本身来说，作者更希望通过JVM这个平台对寄主语言(Java)提供一种补充，只不过是通过LISP的方式。

## 封装与多态性

封装和多态性是面向对象编程语言的两大特性，松本行弘认为

> 面向对象的设计方法是在结构化编程对控制流程实现了结构化后，又加上了对数据的结构化

>  - 不需要知道内部的详细处理就可以进行操作(封装，数据抽象)
>  - 根据不通的数据类型自动选择适当的方法(多态性)


Java利用类和接口虽然解决了很多设计问题，但是看上去还是不够优雅，比如类不能多继承，所以Clojure希望通过更彻底的方式来做到更高级的抽象。

## 认识Java的类

在拥有了基本的数据结构(set,vector,list,map)之后，我们就可以依赖这些基础数据结构构建我们模型，通过组合的方式来表达业务领域，在Java中是这样的：
```
Class User {
    private String name;   //数据
    private int age;       //数据
    ....
    public String getName(){ //行为
        ....
    }
    public void setName(String name){ //行为
        ....
    }
}
```
但这个POJO将数据和行为交织在一起，如果在行为中没有任何业务逻辑，仅仅是暴露数据给外部，在领域驱动设计中这叫贫血对象，根据个人的经验，这样的贫血对象设计在很多Java系统都存在。

## 数据与行为分离

所以，Clojure提供更明确的方式，数据必须具有不可变性(函数式编程特性)，行为是在更搞层次抽象。Clojure提供了[deftype](http://clojuredocs.org/clojure.core/deftype)，[defrecord](http://clojuredocs.org/clojure.core/defrecord)，[reify](http://clojuredocs.org/clojure.core/reify), [defprotocol](http://clojuredocs.org/clojure.core/defprotocol)来实现这个目的，他们就是[Clojure的数据类型](https://clojure.org/reference/datatypes)。deftype可以理解为Java中的class，defprotocol对应Java中的interface，但在Clojure中他们具有更灵活的方式。

## defprotocol

在Java里通过interface来定义规格，一个类可以实现多个interface，子类可以重写父类的方法来实现多态。但在Clojure里面我们不需要新增一个子类来实现多态。例如:
```
(defprotocol Dateable
  (to-ms [t])) ;定义一个包含to-ms方法的接口

(extend java.util.Date
  Dateable
  {:to-ms #(.getTime %)})    ;java.util.Date实现了这个接口

(to-ms (java.util.Date.))  ;java.util.Date具备了to-ms方法

```
在Java中可以通过继承或者组合的方式实现对原有类的扩展，但是会显得很笨粗，Clojure避免了不必要的多层次封装/适配，在不修改原有类同时不新增类的基础上实现了真正的多态性。defprotocol 除了可以被deftype,defrecord,reify实现外，也可以被Java中的类实现。 

## defrecord

defrecord在Clojure里面可以理解为是另外一种map变形方式,例如一个定义User领域模型的map为:
```
(def user {"name" "xiebiao" , "age" 30})
(:name user)

```
用defrecord来表达:
```
(defrecord User [name age])  ;对应Java的Class User
(def user (->User "xiebiao" 30)) ;创建一个user对象
(:name user )   ;获取user对象的name数据

```
既然这样Clojure为什么还需要defrecord呢？这有两方面考虑，和defprotocol一样，需要和Java交互，因为Java是强类型的语言，另一方面，defrecord在应用领域设计中更能体现数据抽象。

defrecord 也可以实现defprotocol:
```
(defprotocol IA
  (say [this])) ;

(defrecord User [name age]
IA
(say [this] (println (:name this))))

(say (->User "xiebiao" 30) )
```
也可以实现多个defprotocol:
```
(defprotocol IA
  (say [this])) ;
(defprotocol IB
  (talk [this])) 

(defrecord User [name age]
IA
(say [this] (println (:name this)))
IB
(talk [this] (println (:name this)))
)

(def user (->User "xiebiao" 30) )
(say user )
(talk user )
```
上面的例子可以看出，通过实现defprotocol让数据具备行为，但数据本身不定义行为。
## deftype
deftype具有类似的语法定义，但是deftype强调的是数据类型，Clojure利用类型分发来实现的多态性。
```
(deftype Circle [radius]) ;定义两个不通的类型
(deftype Square [length width])

(defmethod area Circle [c]
    (* Math/PI (* (.radius c) (.radius c))))
(defmethod area Square [s]
    (* (.length s) (.width s)))

;; create a couple shapes and get their area
(def myCircle (Circle. 10))
(def mySquare (Square. 5 11))

(area myCircle); area方法会根据参数的类型决定调用哪个方法。
(area mySquare)

```
当然Clojure通过defmulti 可以定义更灵活的分发规则，这里只是其中一个根据数据类型分发的例子。

## 为什么有defrecord和deftype?
Clojure官方文档解释了为什么有defrecord和deftype,他们之间的异同，Clojure推荐将领域数据映射到defrecord中，一方面它的底层是不可变的map结构，属于基础的数据结构，以达到语言层面的重用。

## 最后
Clojure虽然是一门LISP方言，LISP语言本身语法结构很简单，但是Clojure实现了纯粹的面向对象语言特性，特别是对当下面向对象编程语言的诟病，值得我们思考学习。
