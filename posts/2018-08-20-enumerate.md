---
layout: post
title: Keeping track of index in ranged-for loops
tags: c++ silly enumeration
---

Sometimes when iterating through a container, we have a need for not just the element at a position, but also the position itself.

For example - let's say we want to iterate through a container or array of some size and set its values from 1 to its size (although, if you really want to do this, you should use `std::itoa` - [link to cppreference](https://en.cppreference.com/w/cpp/algorithm/iota))

In ancient times, back in prehistoric days of C, we might have done something like this:
```c
#include <stdio.h>

#define SIZE /* Some value */

int data[SIZE] = {0};

for (int i = 0; i < 1024; ++i) 
{
  data[i] = i+1;
}
```
Doing this, we're able to use our indexing value as a sort of reference point as we work our way through assigning the values 1.._SIZE_.

But - Ugh! Using an offset value on a raw pointer? Gross! And what about data structures that AREN'T contiguous in memory, like linked lists (in a time where they were still considered relevant)? We'd have to use an entirely different interface!

But hey, we're C++ programmers - we can do better. And abstraction is something we all strive for. Jumping forward to C++98 - the iterator was born.

```cpp
// Pre-C++11
#include <??????> // Mystery type.

std::??????<int> data;
std::??????<int>::iterator it;

int count = 1; // Separate count variable?
for (it = data.begin(); it != data.end(); ++data)
{
  *it = count++;
}

```
From just the interface, try and guess what type `data` is. You can't! And that's a pretty good thing. A consistent, uniform interface between containers is not only easier to use, but also means that a fickle programmer can easily switch between containers if their needs change. But, with this, we've had to declare a separate variable to hold our count. We COULD use `std::distance`, but what if, again, the data was in a data structure which was non-contiguous in memory, and perhaps had _O(n)_ lookup time - say, a linked list? Then, this would become an _O(n<sup>2</sup>)_ operation, and nobody wants that!

Also, that's a bit of a mouthful, and what if the programmer decided they wanted to reverse the direction of the numbers and use a `reverse_iterator` instead? Then they'd need to change the declaration, too! There are distinct `begin()` and `rbegin()` functions as well, so those would also have to be changed!

Thus, enter the function template `std::for_each` to solve this problem. By deducing the type of the begin and end iterators, the following syntax can be used:

```cpp
// Pre-C++11
#include <algorithm>
#include <vector>

const int SIZE = /* Whatever you want it to be. */;

int main()
{
  std::vector<int> v(SIZE);
  std::for_each(v.begin(), v.end(), /* Some sort of counter function call */);
}
```
Great - now we don't need to explicitly declare a our iterators. But what do we put as the function? Whatever the function is, it needs to hold state - our counter variable. We _could_ use a static function for this case in particular, but let's pretend that we need to perform this operation to a number of containers. Also, there's a bad code smell here - the function can only be used once! If we were really set on using a function, we could have a static `resetCount()` function, but that's just silly.

Therefore, we could use an instance of a state-holding callable object which holds the count, like so:

```cpp
// Pre-C++11
struct SetToCounter
{
  int i;

  Counter() : i(0) {}

  template <typename T>
  void operator()(T &elem)
  {
    elem = i++;
  }
};
```
Then, the `for_each` call becomes:

```cpp
// Pre-C++11
std::for_each(v.begin(), v.end(), SetToCounter()); // Yay, no counter variable at callsite.
```

Now, that's alright - but, in our quest to be more succinct, we've ended up with more lines of code - an entire new class's worth!

C++11, in addition to other things, introduced ranged-for loops. Now, even the calls to `begin()` and `end()` were no longer needed!

```cpp
// And we're finally at Modern C++.
#include <vector>

constexpr int SIZE = /* Whatever you want it to be. */;

std::vector<int> v(SIZE);

int i = 0;
for (auto &elem : v)
{
  elem = i++;
}
```

Yet again, we need a separate counter variable. At this point, is it even worth using the ranged-for if we need to keep track of an index anyway? But with the ranged-for, I like not having to use call `size()`, and I like the ability to directly use a reference to each element in the array. Furthermore, as ranged for loops use iterators under the hood, traversing data structures that don't have an _O(1)_ access time does not incur a performance penalty, as the container doesn't need to be re-traversed every loop!

While learning some Rust, I came across the following functionality:

```rust
let mut v = Vec::new();
// yada yada yada
for (index, &item) in v.iter().enumerate() {
  // Do something with index and item.
}
```
Simple and succinct - we want to iterate through `v`, and enumerate that. The syntax is easily readable, and the intent is clear. Not only do we get the element at that location, we also get what location it is itself!

So, to replicate this syntax, I've written an enumerating iterator [here](https://github.com/jumbatm/enumerate). It simply sits on top of a container's iterator and tracks an index value with it. It's worth mentioning that no use of the index operator is used, avoiding the inefficiency I've described above.

Using `enumerate`, we can solve our problem with the following syntax:

```cpp
// C++17+
#include <vector>

constexpr int SIZE = /* Whatever you want it to be. */;

std::vector<int> v(SIZE);

for (auto &&[index, elem] : jon::enumerate(v))
{
  elem = index;
}

```
It uses [structured bindings](https://en.cppreference.com/w/cpp/language/structured_binding) for this syntax, so C++17 is needed. Under the hood, `enumerate` returns a `std::pair`, so the following syntax could also be used instead:

```cpp
// Not quite C++11 unfortunately, 
// because enumerate's begin() and 
// end() currently have different return types.
for (auto pair : jon::enumerate(v))
{
  auto index = pair.first;
  auto &elem = pair.second;
  // ... yada yada yada
```
But I don't think that looks as nice.

Anyway, looking into the future, we'll have [Ranges](https://ericniebler.github.io/std/wg21/D4128.html), which will change the way we think about performing operations on a container completely - and we might not even need to be looping through our containers anymore.
