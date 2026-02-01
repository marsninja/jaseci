// Basic TypeScript declarations for parser testing
export const API_URL: string = "https://api.example.com";
export let count: number = 0;
export var legacy: boolean = true;

export function greet(name: string): string {
  return `Hello, ${name}!`;
}

export async function fetchData(url: string, timeout: number): Promise<string> {
  const response = await fetch(url);
  return response.text();
}

export interface Todo {
  id: number;
  title: string;
  completed: boolean;
  tags: string[];
  metadata?: Record<string, unknown>;
}

export interface TodoService {
  getTodos(): Promise<Todo[]>;
  addTodo(title: string): Promise<Todo>;
  toggleTodo(id: number): Promise<void>;
}

export class TodoApp implements TodoService {
  private todos: Todo[] = [];
  public readonly name: string;

  constructor(name: string) {
    this.name = name;
  }

  async getTodos(): Promise<Todo[]> {
    return this.todos;
  }

  async addTodo(title: string): Promise<Todo> {
    const todo: Todo = { id: Date.now(), title, completed: false, tags: [] };
    this.todos.push(todo);
    return todo;
  }

  async toggleTodo(id: number): Promise<void> {
    const todo = this.todos.find(t => t.id === id);
    if (todo) todo.completed = !todo.completed;
  }

  static create(name: string): TodoApp {
    return new TodoApp(name);
  }
}

export type Status = "active" | "completed" | "archived";

export enum Priority {
  LOW = 0,
  MEDIUM = 1,
  HIGH = 2,
  CRITICAL = 3,
}

export default TodoApp;
