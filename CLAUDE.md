@AGENTS.md

## Claude Code 补充

- 用中文回复。
- 这台开发机是 Windows：Bash 工具是 Git Bash，`py -3` 是 Python。反斜杠转义在 heredoc 和编辑工具里可能被展开，含 `\u`、`\n` 这类内容的文件，先用 Write 写成脚本再运行。用 Python 改仓库文件时按字节读写（`read_bytes`/`write_bytes`）：`write_text` 在 Windows 上会把换行写成 CRLF。
- 只结束自己启动的进程；不要改系统设置或注册表，需要时请用户操作（例如开发者模式）。
- 提交和推送到本项目已获授权；发布 Release、部署网站、写 CI 变量这类对外操作，先确认用户确实要做。
