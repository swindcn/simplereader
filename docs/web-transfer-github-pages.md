# 简声网站传书 GitHub Pages 部署

网站传书前端位于 `web-transfer/`，后端接口继续使用 Supabase Edge Function：

`https://nzksxspznpkquybprqms.supabase.co/functions/v1/transfer`

## 部署方式

1. 将代码推送到 GitHub 仓库的 `main` 分支。
2. 打开 GitHub 仓库的 `Settings` -> `Pages`。
3. 将 `Build and deployment` 的 `Source` 设置为 `GitHub Actions`。
4. 打开 `Actions`，运行 `Deploy Web Transfer Page`，或推送 `web-transfer/**` 后等待自动部署。

部署完成后，页面地址会显示在 Action 的 `github-pages` 环境中。

## 测试流程

1. 在简声 App 的“网站传书”页面生成或查看传书码。
2. 在 GitHub Pages 页面输入 8 位传书码。
3. 选择 TXT 或 EPUB 文件并上传。
4. 回到 App 刷新待接收文件。
5. 接收成功后确认书籍已导入书架。
