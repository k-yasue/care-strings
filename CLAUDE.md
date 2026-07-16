@AGENTS.md

## プロジェクト概要

CareStrings — 介護施設向け申し送り共有アプリ(ポートフォリオ)。
設計書は docs/ 参照(requirements / db_design / wireframe)。
DBスキーマは supabase/migrations/001_initial_schema.sql(適用済み・12テーブル)。

## 技術構成

- Next.js (App Router) + TypeScript / Supabase (PostgreSQL + Auth + Storage)
- フェーズ2でAPI層をGo+GraphQL(gqlgen)に移行予定。今はSupabase直結
- ふりがな: kuroshiro(クライアント側生成) / i18n: next-intl(後で導入)

## 実装ルール(重要)

- サインアップ(自由登録)画面は作らない。アカウントは管理者が招待発行
- 投稿(posts)とコメント(post_comments)は編集・削除機能を作らない(記録の信頼性のため)
- 権限チェックはRLS前提だがUI側の出し分けも実装する(admin機能等)
- タイムライン系の取得は必ずページネーション(全件取得禁止)
- 実在の個人情報は絶対に扱わない。シード・テストデータはすべて架空
- DBスキーマ変更時は supabase/migrations/ に連番SQLを追加(既存ファイルは変更しない)

## コード規約

- コミットメッセージは英語(例: "feat: add login page")
- 日本語UIがデフォルト。文言は後でi18n化するためベタ書きしすぎない
