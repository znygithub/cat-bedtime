# 文档规范

文档结构见 [`.rule.md`](.rule.md)。**`ARCHITECTURE.md` + `docs/`** 是唯一入口。

## 必读与按需阅读

| 文档 | 何时读 |
|------|--------|
| [`docs/core-beliefs.md`](docs/core-beliefs.md) | 首次接触；产品哲学、边界、路线 |
| [`ARCHITECTURE.md`](ARCHITECTURE.md) | 目录结构、运行时数据、全局流程、测试 |
| [`docs/tech-docs/index.md`](docs/tech-docs/index.md) | 技术索引、代码入口 |
| [`docs/product-specs/index.md`](docs/product-specs/index.md) | 按模块读需求 |
| [`docs/RELIABILITY.md`](docs/RELIABILITY.md) | 改 daemon / overlay / CLI 交互前 |

## 文档结构

```text
ARCHITECTURE.md
docs/
├── core-beliefs.md
├── PRODUCT_SENSE.md
├── PLANS.md
├── DESIGN.md
├── FRONTEND.md
├── QUALITY_SCORE.md
├── RELIABILITY.md
├── SECURITY.md
├── tech-docs/
├── product-specs/
├── exec-plans/
├── generated/
└── references/
```

## 维护规则

代码变更后：

1. 更新对应的 `docs/product-specs/` 或 `docs/tech-docs/` 文档
2. 若影响全局架构或数据契约，同步 `ARCHITECTURE.md`
3. 若影响产品边界或路线，同步 `docs/core-beliefs.md`、`docs/PLANS.md`
4. 若影响 UI，同步 `docs/DESIGN.md`、`docs/FRONTEND.md`
5. 若新增踩坑，写入 `docs/RELIABILITY.md`

## AI 使用提示

- 改代码前：读 `core-beliefs.md` + `ARCHITECTURE.md`，再读目标模块 spec / tech doc
- 行为描述须与代码一致；有歧义以代码为准
