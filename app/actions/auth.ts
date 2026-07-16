'use server'

import { redirect } from 'next/navigation'
import { revalidatePath } from 'next/cache'
import { createClient } from '@/utils/supabase/server'

// 文言は後でi18n辞書へ移す想定のため1箇所にまとめる
const messages = {
  required: 'メールアドレスとパスワードを入力してください',
  // 「メールが存在しない」と「パスワードが違う」を区別しない:
  // アカウントの存在有無を攻撃者に教えないため
  invalid: 'メールアドレスまたはパスワードが正しくありません',
} as const

export type LoginState = {
  error: string | null
}

export async function login(
  _prevState: LoginState,
  formData: FormData
): Promise<LoginState> {
  const email = String(formData.get('email') ?? '').trim()
  const password = String(formData.get('password') ?? '')

  if (!email || !password) {
    return { error: messages.required }
  }

  const supabase = await createClient()
  const { error } = await supabase.auth.signInWithPassword({ email, password })

  if (error) {
    return { error: messages.invalid }
  }

  // ログイン後はセッションが変わるため、キャッシュ済みの画面を捨てて描画し直す
  revalidatePath('/', 'layout')
  redirect('/')
}

export async function logout() {
  const supabase = await createClient()
  await supabase.auth.signOut()

  revalidatePath('/', 'layout')
  redirect('/login')
}
