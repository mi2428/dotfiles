export type TodoItem = {
  content: string;
  status: string;
  priority?: string;
};

export type TodoLineKind = "in_progress" | "pending" | "other";

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
};

const STATUS_ORDER: Readonly<Record<string, number>> = {
  in_progress: 0,
  pending: 1,
};

function statusRank(status: string): number {
  return STATUS_ORDER[status] ?? 2;
}

function compactContent(content: string): string {
  return content.replace(/\s+/g, " ").trim();
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
  if (activeTodos.length === 0) return null;

  const lines: TodoLine[] = activeTodos.map((todo) => ({
    kind: todo.status === "in_progress" ? "in_progress" : todo.status === "pending" ? "pending" : "other",
    text: `${todo.status === "in_progress" ? "▶" : todo.status === "pending" ? "·" : "?"} ${compactContent(todo.content)}`,
  }));

  return {
    total: todos.length,
    active: activeTodos.length,
    completed,
    cancelled,
    lines,
  };
}
