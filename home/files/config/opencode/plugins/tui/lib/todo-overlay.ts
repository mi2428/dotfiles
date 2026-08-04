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
  cancelled: number;
  lines: TodoLine[];
  windowStart: number;
  windowEnd: number;
};

const MAX_IN_PROGRESS = 1;
const TODO_WINDOW_SIZE = 5;
const TODO_WINDOW_RADIUS = Math.floor(TODO_WINDOW_SIZE / 2);
const BULLET = "▸";

function compactContent(content: string): string {
  return content.replace(/\s+/g, " ").trim();
}

export function normalizeTodos(input: readonly TodoItem[] | null | undefined): TodoItem[] {
  if (!input) return [];
  return input
    .filter((todo): todo is TodoItem => Boolean(todo) && typeof todo.content === "string")
    .map((todo) => ({ ...todo, status: typeof todo.status === "string" ? todo.status : "pending" }));
}

export function buildTodoView(input: readonly TodoItem[] | null | undefined): TodoView | null {
  const todos = normalizeTodos(input);
  if (todos.length === 0) return null;

  const completedTodos = todos.filter((todo) => todo.status === "completed");
  const inProgress = todos.filter((todo) => todo.status === "in_progress");
  const pending = todos.filter((todo) => todo.status === "pending");
  const completed = completedTodos.length;
  const cancelled = todos.filter((todo) => todo.status === "cancelled").length;
  const currentTodos = inProgress.slice(0, MAX_IN_PROGRESS);
  const lines: TodoLine[] = [
    ...completedTodos.map((todo): TodoLine => ({
      kind: "completed",
      text: `${BULLET} ${compactContent(todo.content)}`,
    })),
    ...currentTodos.map((todo): TodoLine => ({
      kind: "in_progress",
      text: `${BULLET} ${compactContent(todo.content)}`,
    })),
    ...pending.map((todo): TodoLine => ({
      kind: "pending",
      text: `${BULLET} ${compactContent(todo.content)}`,
    })),
  ];
  if (lines.length === 0) return null;

  const currentIndex = currentTodos.length > 0 ? completedTodos.length : undefined;
  const windowStart = currentIndex === undefined
    ? pending.length > 0
      ? 0
      : Math.max(0, lines.length - TODO_WINDOW_SIZE)
    : Math.max(0, currentIndex - TODO_WINDOW_RADIUS);
  const windowEnd = currentIndex === undefined
    ? Math.min(lines.length - 1, windowStart + TODO_WINDOW_SIZE - 1)
    : Math.min(lines.length - 1, currentIndex + TODO_WINDOW_RADIUS);

  return {
    total: completed + inProgress.length + pending.length,
    active: inProgress.length + pending.length,
    completed,
    cancelled,
    lines,
    windowStart,
    windowEnd,
  };
}
