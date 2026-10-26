# Contributing

## 提交规范

本仓库所有提交信息采用 Conventional Commits，提交说明使用中文。

推荐格式：

```text
<type>: <中文说明>
```

常用类型：

- `feat`: 新功能
- `fix`: 问题修复
- `refactor`: 重构
- `docs`: 文档更新
- `test`: 测试相关
- `chore`: 工程、配置、依赖、脚本调整
- `perf`: 性能优化

示例：

```text
feat: 搭建 iOS MVP 工程骨架
fix: 修复录音恢复后时长累加错误
docs: 补充 iOS 核心 MVP 重构计划
chore: 配置 Xcode 项目与 SwiftData 容器
```

## Git 工作约定

- 每个提交只包含一个清晰、完整的逻辑变更。
- 提交前确保工程可编译，必要测试通过。
- 不提交本地缓存、派生构建产物和个人配置文件。
- 优先在本地完成小步提交，保持历史可回滚、可审阅。

