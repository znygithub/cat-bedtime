这是项目的文件目录，根据你当前的任务，维护和查阅相关有关文档，不需要一口气阅读所有文档

当代码做出调整后，也请维护相关文档，保持文档和代码是同步的

我下的需求和指令应该先进plan，plan是会动态不断变化的，刷新频率高，需求文档是现有项目的现状，刷新频率较低，我让你刷新后你基于plan的历史进行刷新

ARCHITECTURE.md
docs/
├── core-beliefs.md  #产品设计的核心理念，必读
├── tech-docs/  #技术架构
│   ├── index.md
│   └── ...
├── task/ # 如果遇到复杂任务，先写任务plan到task文件，积极维护这个文件，这是任务的起点，要写一下任务时间
│   ├── active/  #正在执行的task，需要写清楚产品需求、技术方案、验收标准
│   ├── completed/ #我没有异议和没有后续调整的，进行归档，自动归档条件：该任务已经过去半小时了没有修改
│   └── tech-debt-tracker.md 
├── generated/
│   └── db-schema.md
├── product-specs/ #需求文档，详细写明产品的需求内容，不许出现技术语言
│   ├── index.md
│   ├── new-user-onboarding.md
│   └── ...
├── references/ # 可能会使用的参考资料
│   └── ...
├── DESIGN.md
├── FRONTEND.md
├── FUTURE_Plan.md  #未来可能的改进，由我编写
├── PRODUCT_SENSE.md
├── QUALITY_SCORE.md
├── RELIABILITY.md
└── SECURITY.md

## 发版提醒

每次发布新版本时，必须同步更新 `README.md` 和 `README_EN.md` 里的 GitHub Release 下载链接，让 DMG 和 CLI 链接指向最新 tag。否则用户会继续下载旧包，可能遇到旧包缺少 `assets/cat-bedtime.mov` 导致睡眠动画显示“缺少猫猫动画素材”。
