export type TodoItem = {
  content: string;
  status: string;
  priority?: string;
};

export type TodoLineKind = "completed" | "in_progress" | "pending";

export type TodoLine = {
  kind: TodoLineKind;
  text: string;
};

export type TodoView = {
  total: number;
  active: number;
  completed: number;
  summary: boolean;
  lines: TodoLine[];
};

const BULLETS = { completed: "✓", in_progress: "▶", pending: "○" };

function compactContent(content: string): string {
  return content.replace(/\s+/g, " ").trim();
}

export function normalizeTodos(input: readonly TodoItem[] | null | undefined): TodoItem[] {
  if (!input) return [];
  return input
    .filter((todo): todo is TodoItem => Boolean(todo) && typeof todo.content === "string")
    .map((todo) => ({ ...todo, status: typeof todo.status === "string" ? todo.status : "pending" }));
}

export function buildTodoView(input: readonly TodoItem[] | null | undefined, rowLimit: number): TodoView | null {
  const todos = normalizeTodos(input).filter((todo) => ["completed", "in_progress", "pending"].includes(todo.status));
  const finished = todos.filter((todo) => todo.status === "completed");
  const completed = finished.length;
  const active = todos.length - completed;
  if (active === 0) return null;
  const summary = todos.length > rowLimit;
  const taskLimit = rowLimit - Number(summary);
  const upcoming = [
    ...todos.filter((todo) => todo.status === "in_progress"),
    ...todos.filter((todo) => todo.status === "pending"),
  ];
  const previous = finished.slice(Math.max(0, finished.length - Math.max(0, taskLimit - upcoming.length)));
  const lines = [...previous, ...upcoming.slice(0, taskLimit)].map((todo): TodoLine => ({
    kind: todo.status as TodoLineKind,
    text: `${BULLETS[todo.status as TodoLineKind]} ${compactContent(todo.content)}`,
  }));
  return {
    total: todos.length,
    active,
    completed,
    summary,
    lines,
  };
}
