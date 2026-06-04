// agent.js — reusable agent runner used by dashboard
import { apiFetch } from "./api.js"

export async function runFieldAgent(fieldId) {
  return apiFetch(`/analytics/field/${fieldId}/run-agent`, {
    method: "POST"
  })
}