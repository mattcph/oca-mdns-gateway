# Locked third-party revisions

Dependencies live as **Git submodules** under [`third_party/`](third_party/). After `git submodule update --init --recursive`, CMake uses these paths directly (no FetchContent for these libraries).

| Submodule | Repository | Pinned ref | Commit |
|-----------|------------|------------|--------|
| `third_party/mdnscpp` | [arneg/mdnscpp](https://github.com/arneg/mdnscpp) | `5dca496` (Version 1.0.3) | `5dca49622cf345b918c8e4ce3bdbf32ec7bfa9c0` |
| `third_party/cpp-httplib` | [yhirose/cpp-httplib](https://github.com/yhirose/cpp-httplib) | tag `v0.18.3` | `a7bc00e3307fecdb4d67545e93be7b88cfb1e186` |
| `third_party/json` | [nlohmann/json](https://github.com/nlohmann/json) | tag `v3.11.3` | `9cca280a4d0ccf0c08f47a99aa71d1b0e52f8d03` |

To refresh this table after bumping a submodule:

```bash
git submodule status
```
