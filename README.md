# traceable
A improved [cloudwu's tracedoc](https://github.com/cloudwu/tracedoc) implementation.

## Improvement
- `traceable` 对象的 `__index` 是一个 `table` 而不是 `function`，索引效率更高;
- 同时，`#`、`next`、`pairs`、`ipairs`、`unpack` 等操作的操作也更直接和高效;
- 在 `commit` 的同时应用 `mapping` 而无需顺序执行两者;
- 同时，`commit` 不再需要真的生成差异集，亦无需执行字符串拼接（`..`）操作;
- 该项目带有基于 [busted](http://olivinelabs.com/busted/) 的单元测试;

特别感谢 [recih 的改进版本](https://github.com/recih/tracedoc)
