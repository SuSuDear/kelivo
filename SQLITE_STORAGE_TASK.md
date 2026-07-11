# SQLite 聊天存储加固任务

## 目标

将当前 SQLite JSON-KV 过渡实现改造成可验证、可恢复、具备事务一致性的 iOS 聊天存储，并逐步迁移到规范化关系表。

## 成功标准

- 发送一条消息时，消息和会话引用原子提交。
- 删除消息、会话、助手关联会话时，不留下孤立记录。
- 流式延迟写入不会在删除后复活消息。
- 任一写入失败后，同一记录后续仍可继续写入。
- 清空数据前等待或取消全部待写任务，并在单一事务中清空。
- SQLite 初始化可并发调用、失败后可重试。
- 数据库异常有明确日志，不再表现为按钮静默无响应。
- 最终表结构包含外键、必要索引和可升级 schema 版本。

## P0：稳定性加固

- [x] 修复 per-key 写队列被失败 Future 污染的问题
- [x] 增加全局 `flush` / 单 key `flush` / 取消待写 API
- [x] 添加消息与更新会话使用单一事务
- [x] 删除消息和相关工具数据使用单一事务
- [x] 删除会话及其消息/工具数据使用单一事务
- [x] 清空聊天数据使用单一事务
- [x] 删除和清空前取消流式延迟写入
- [x] 数据库写失败时恢复内存缓存
- [x] 初始化、发送、删除错误输出明确日志
- [x] 静态检查：无 Hive 运行引用、`git diff --check`

## P1：关系化 schema

- [ ] schema v2：规范化 `conversations` 表
- [ ] schema v2：规范化 `messages` 表并设置 `ON DELETE CASCADE`
- [ ] schema v2：规范化 `tool_events` / 消息辅助数据
- [ ] 建立会话更新时间、消息顺序、助手 ID 索引
- [ ] 编写 v1 JSON-KV → v2 迁移事务
- [ ] 启动后执行 `foreign_key_check` / `integrity_check` 调试验证
- [ ] 分页读取不再依赖全量载入

## 验证记录

- 当前数据库 `PRAGMA integrity_check`：`ok`
- 当前 schema：v1 JSON-KV（待加固和迁移）
- 当前运行数据：1 个会话、3 条消息
- 设备无 Flutter SDK：需由 CI 或构建机补充 `flutter analyze` 与测试

### 2026-07-11 P0 实施记录

- `SqliteJsonStore` 写队列在前一写入失败后可继续执行。
- 写入成功后才更新内存缓存；事务失败时恢复会话内存快照。
- 添加消息、删除消息、删除会话、清空数据均使用 SQLite transaction。
- 删除和清空会取消流式延迟定时器，并等待已经开始的 SQL 写入。
- 初始化采用共享 Future，失败后可重试。
- 关键事务失败会输出 `debugPrint` 日志并向上传播。
- `git diff --check` 通过；当前数据库 `integrity_check=ok`。
- 设备无 Dart/Flutter SDK，编译、analyze 和行为测试仍需 CI/构建机完成。
