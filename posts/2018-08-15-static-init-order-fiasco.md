---
layout: post
date: 2018-08-15
title: "The Static Init Fiasco Fiasco (and why global variables are even more evil than you think!)"
tags: c++ debugging
---

First of all, first blog post!

```cpp
std::cout << "Hello world!\n";
```

Although [learncpp.com](https://learncpp.com) teaches C before teaching C++ (which we should [strive to avoid](https://www.youtube.com/watch?v=YnWhqhNdYyk)), as someone who wanted to learn C anyway, I found it to be a good resource to get started with when I decided to start learning C++ about a year ago.

One thing I clearly remember is the section [Why Global Variables Are Evil](http://www.learncpp.com/cpp-tutorial/4-2a-why-global-variables-are-evil/) (largely due to the hilarious joke at the bottom). It does a great job explaining many of the common reasons people strive to avoid global variables - reasons like that they're hard to track and too easy to mutate. But, I have yet another reason they are _evil_.

Earlier this week, I was writing some tests for a lazily-evaluated Matrix class I've been working on for one of my university classes, using [Catch Tiny](https://www.github.com/jumbatm/catch-tiny), a small (and rather buggy) subset of Catch2 that I wrote because I don't like my _tests_ having long compile times.

So, I wrote my tests, ran the compiler, and...

```
[1]    15270 floating point exception (core dumped)
```

... Well then. That's unexpected. Furthermore, depending on which tests I compiled with, this error would sometimes happen and sometimes wouldn't. If I didn't compiled it with a certain combination of files, it would not show SIGFPE, but without those files, it would work and work every single time. Very strange!

So I fired up ol' trusty [cgdb](https://cgdb.github.io/), and quickly found the line of code responsible, nested deep somewhere in the standard library:

```cpp
 427|     typedef std::size_t first_argument_type;
 428|     typedef std::size_t second_argument_type;
 429|     typedef std::size_t result_type;
 430|
 431|     result_type
 432|     operator()(first_argument_type __num,
 433|                second_argument_type __den) const noexcept
 434|---> { return __num % __den; }
 435|   };
 436|
 437|   /// Default ranged hash function H.  In principle it should be a
 438|   /// function object composed from objects of type H1 and H2 such that
 439|   /// h(k, N) = h2(h1(k), N), but that would mean making extra copies of
 440|   /// h1 and h2.  So instead we'll just use a tag to tell class template
...
Program received signal SIGFPE, Arithmetic exception.
0x0000000000413e18 in std::__detail::_Mod_range_hashing::operator() (this=0x61e3d8 <TestCase::allTestCases[abi:cxx11]>, __num=15930331572883865028, __den=0) at /usr/bin/../lib/gcc/x86_6
4-linux-gnu/8/../../../../include/c++/8/bits/hashtable_policy.h:434
```

I could see that this exception occurred due to division by zero (from `__den`, which is determined by the hashmap's bucket count being 0). Walking up the callstack a bit I saw that this was being thrown at the point of declaration of a `TEST_CASE`:

```cpp
17|>TEST_CASE("Matrices are zero-initialised, no matter the size")
18| {
19|     // Perform this test 10 times.
20|     for (size_t i = 0; i < 10; ++i)
```

Specifically, at this line in `catch.hpp`:

```cpp
109| TestCase::TestCase(const char *filename,
110|                    const char *name,
111|                    void (*function)(TestCase *))
112|   : name(name), function(function)
113| {
114|     TestCase::count++;
115|---> allTestCases[std::string(filename)].push_back(*this);
116|     if (!testCaseNames.insert(std::string(name)).second)
117|     {
118|         CATCH_INTERNAL(duplicateTestCaseName) = name;
119|     }
120| }
```
<sup>[That's this line on this commit.](https://github.com/jumbatm/catch-tiny/blob/dabff30061e8742ae9e9ee3d8e4de35974acdf7d/include/catch.hpp#L122), if you want to browse around yourself.</sup>

To give a bit of context: everytime the `TEST_CASE` macro is used to declare a new test case, an object of type `TestCase` is created (as a global variable). On construction, it appends (a copy of) itself to a list of `TestCase`s, after indexing a static `unordered_map` to figure out which list (as there's one for every file) to add itself to.

Further investigation showed that this divide-by-zero was being thrown before `main()` even began, in the magical land of static initialisation, before the first statement in `main()` was even run. A small test program showed that in a working program, the bucket count should be 1 at a minimum. So why was this occurring?

After much hair pulling, I realised it was due to the `TEST_CASE` being initialised before `TestCase::allTestCases` was - in other words, the test case was trying to add itself to an uninitialised `unordered_map`. Typically, I think about uninitialised memory as giving garbage values which change at runtime due to unzero'd, leftover memory from a previous process and virtual addressing. What I _didn't_ know was that static-duration objects (which persist from program start all the way to its termination - so global variables and static class variables) are located in memory which is zero'd on startup - the .bss segment. Therefore, the bucket count was being _read_ as zero.

In fact, we can see this if we look at the raw bytes representing the `unordered_map` in cgdb. This is what `TestCase::allTestCases` looks like at this point:

```cpp
(gdb) p sizeof(allTestCases)
$3 = 56
(gdb) p (char[56])allTestCases
$4 = '\000' <repeats 55 times>
(gdb) 
```
<sup>All zeros!</sup>

but in a working example, an initialised but empty map looks like this:

```cpp
Breakpoint 3, __static_initialization_and_destruction_0 (__initialize_p=1, __priority=65535
) at main.cpp:11
(gdb) p (char[56])g_map
$2 = "\360P`\000\000\000\000\000\001", '\000' <repeats 25 times>, "\200?", '\000' <repeats
19 times>
```
<sup>I like to imagine that the little `\001` is the correctly-initialised bucket value of 1.</sup>

For global variables in a single translation unit, it's easy to make sure things are initialised in the right order. But what happens for global variables accessible in multiple translation units? What order are they initialised in, then? Well, it turns out there's no guaranteed order that they'll be initialised in. This is known as the "static initialisation order fiasco". Turns out, I live under a rock - it's well-known enough that [ISO C++ even has a page on it](https://isocpp.org/wiki/faq/ctors#static-init-order).

We can ensure initialisation prior to use by changing the global variable to be a static variable inside a getter function, like so:

```cpp
std::unordered_map<std::string, std::list<TestCase>>
    &TestCase::getAllTestCases()
{
    static std::unordered_map<std::string, std::list<TestCase>>
        TestCase_allTestCases;
    return TestCase_allTestCases;
}
```

and changing the TestCase constructor to:

```cpp
TestCase::TestCase(const char *filename,
                   const char *name,
                   void (*function)(TestCase *))
  : name(name), function(function)
{
    TestCase::count++;
    TestCase::getAllTestCases()[std::string(filename)].push_back(*this); // Change here.
    if (!TestCase::getTestCaseNames().insert(std::string(name)).second)
    {
        CATCH_INTERNAL(duplicateTestCaseName) = name;
    }
}
```
That way, the variable will definitely be initialised before the first time it's used.

It really says something about the philosophy of C++ - you really do only get the checks you pay for!
