import { apiFetch, setToken, clearToken } from "./api.js"

export async function login(email, password) {
  const form = new URLSearchParams()
  form.append("username", email)
  form.append("password", password)

  const data = await apiFetch("/auth/login", {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded"
    },
    body: form
  })
  setToken(data.access_token)
  return data
}

export async function register(fullName, email, password, role) {
  return apiFetch("/auth/register", {
    method: "POST",
    body: JSON.stringify({ full_name: fullName, email, password, role })
  })
}

export async function logout() {
  await apiFetch("/auth/logout", { method: "POST" })
  clearToken()
  window.location.href = "../../index.html"
}