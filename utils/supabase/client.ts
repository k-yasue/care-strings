import { createBrowserClient } from '@supabase/ssr'

/**
 * ブラウザ(Client Component)から使う Supabase クライアント。
 * 認証セッションは Cookie に保存され、server.ts 側と共有される。
 */
export function createClient() {
  return createBrowserClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!
  )
}
