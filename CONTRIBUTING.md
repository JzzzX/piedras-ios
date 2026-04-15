# Contributing

CocoInterview uses Conventional Commits. Keep each commit focused on one logical change.

Recommended format:

```text
<type>(scope): <中文说明>
```

Common types:

- `feat`
- `fix`
- `refactor`
- `docs`
- `test`
- `chore`
- `perf`

Examples:

```text
feat(ios): 完成 coco-interview 品牌迁移
fix(api): 修复录音音频上传失败
docs: 重写公开版 README
chore(repo): 清理无关文档与示例目录
```

Guidelines:

- Run the smallest relevant verification before committing.
- Do not commit build products, temporary screenshots, local caches, or personal Xcode settings.
- Keep changes aligned with the existing repo structure unless the rename/refactor is intentional and complete.
- For iOS work, prefer `xcodebuild` verification on the `CocoInterview` scheme.
- For `cloud/api`, make sure `npm run build` still succeeds.
