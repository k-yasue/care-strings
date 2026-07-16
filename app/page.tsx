import { redirect } from 'next/navigation'
import { createClient } from '@/utils/supabase/server'
import { logout } from './actions/auth'

// ※ 仮のホーム画面。本実装は F-04〜07(重要バナー+AI要約+タイムライン)で作る。
//    今は認証が一気通貫で動いていることを確認するための最小構成。

// 文言は後でi18n辞書へ移す想定のため1箇所にまとめる
const t = {
  appName: 'CareStrings',
  signedInAs: 'ログイン中',
  logout: 'ログアウト',
  placeholder: 'ホーム画面はこれから実装します(F-04〜07)。',
} as const

const roleLabels: Record<string, string> = {
  caregiver: '介護職',
  nurse: '看護師',
  admin: '管理者',
}

export default async function HomePage() {
  const supabase = await createClient()

  // proxy.ts でも弾いているが、公式は「proxyだけに頼るな」としているため
  // ページ側でも確認する(getUser は認証サーバーに問い合わせて検証する)
  const {
    data: { user },
  } = await supabase.auth.getUser()

  if (!user) {
    redirect('/login')
  }

  // RLS により、ログインしていなければこの行は取得できない
  const { data: profile } = await supabase
    .from('profiles')
    .select('name, role, unit_id')
    .eq('id', user.id)
    .single()

  return (
    <main className="flex flex-1 flex-col gap-6 p-6">
      <header className="flex items-center justify-between border-b border-black/10 pb-4 dark:border-white/15">
        <h1 className="text-xl font-bold">{t.appName}</h1>
        <form action={logout}>
          <button
            type="submit"
            className="rounded-md border border-black/20 px-3 py-1.5 text-sm dark:border-white/20"
          >
            {t.logout}
          </button>
        </form>
      </header>

      <p className="text-sm">
        {t.signedInAs}: <strong>{profile?.name}</strong>
        {profile?.role && (
          <span className="ml-2 opacity-70">
            ({roleLabels[profile.role] ?? profile.role})
          </span>
        )}
      </p>

      <p className="text-sm opacity-60">{t.placeholder}</p>
    </main>
  )
}
