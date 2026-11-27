export const password: string;
export function api(user: { token: string }, method: string, path: string, body?: unknown): Promise<any>;
export function resetEmulators(): Promise<void>;
export function seedWorld(): Promise<{
  password: string;
  teamId: string;
  users: Record<"ada" | "ben" | "cam", { email: string; uid: string }>;
}>;
