export type TodoItem = {
  content: string;
  status: string;
  priority?: string;
};

export type TodoLineKind = "in_progress" | "pending" | "other" | "summary";

export type TodoLine = {
  kind: TodoLineKind;
  text: string;
};

export type TodoView = {
  total: number;
  active: number;
  completed: number;
  cancelled: number;
  lines: TodoLine[];
  hiddenActive: number;
};

export const MAX_VISIBLE_ACTIVE = 3;
export const MAX_CONTENT_LENGTH = 88;

const STATUS_ORDER: Readonly<Record<string, number>> = {
  in_progress: 0,
  pending: 1,
};

function statusRank(status: string): number {
  return STATUS_ORDER[status] ?? 2;
}

function truncateContent(content: string): string {
  const compact = content.replace(/\s+/g, " ").trim();
  if (compact.length <= MAX_CONTENT_LENGTH) return compact;
  return `${compact.slice(0, MAX_CONTENT_LENGTH - 1)}…`;
}

export function normalizeTodos(input: readonly TodoItem[] | null | undefined): TodoItem[] {
  if (!input) return [];
  return input
    .filter((todo): todo is TodoItem => Boolean(todo) && typeof todo.content === "string")
    .map((todo) => ({ ...todo, status: typeof todo.status === "string" ? todo.status : "pending" }))
    .sort((left, right) => statusRank(left.status) - statusRank(right.status));
}

export function buildTodoView(input: readonly TodoItem[] | null | undefined): TodoView | null {
  const todos = normalizeTodos(input);
  if (todos.length === 0) return null;

  const inProgress = todos.filter((todo) => todo.status === "in_progress");
  const pending = todos.filter((todo) => todo.status === "pending");
  const other = todos.filter(
    (todo) => !["in_progress", "pending", "completed", "cancelled"].includes(todo.status),
  );
  const completed = todos.filter((todo) => todo.status === "completed").length;
  const cancelled = todos.filter((todo) => todo.status === "cancelled").length;
  const activeTodos = [...inProgress, ...pending, ...other];
  const visibleTodos = activeTodos.slice(0, MAX_VISIBLE_ACTIVE);
  const lines: TodoLine[] = visibleTodos.map((todo) => ({
    kind: todo.status === "in_progress" ? "in_progress" : todo.status === "pending" ? "pending" : "other",
    text: `${todo.status === "in_progress" ? "▶" : todo.status === "pending" ? "·" : "?"} ${truncateContent(todo.content)}`,
  }));

  const hiddenActive = Math.max(0, activeTodos.length - visibleTodos.length);
  if (hiddenActive > 0) {
    lines.push({ kind: "summary", text: `… ${hiddenActive} more active` });
  }
  if (completed > 0 || cancelled > 0) {
    const summary = [completed > 0 ? `✓ ${completed} completed` : "", cancelled > 0 ? `× ${cancelled} cancelled` : ""]
      .filter(Boolean)
      .join("  ·  ");
    lines.push({ kind: "summary", text: summary });
  }

  return {
    total: todos.length,
    active: activeTodos.length,
    completed,
    cancelled,
    lines,
    hiddenActive,
  };
}
