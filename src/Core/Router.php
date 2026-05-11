<?php
declare(strict_types=1);

namespace ConectaEduca\Core;

final class Router
{
    private array $routes = [];

    public function get(string $path, callable $handler): void
    {
        $this->add('GET', $path, $handler);
    }

    public function post(string $path, callable $handler): void
    {
        $this->add('POST', $path, $handler);
    }

    private function add(string $method, string $path, callable $handler): void
    {
        $path = '/' . trim($path, '/');
        $this->routes[$method][$path] = $handler;
    }

    public function dispatch(): void
    {
        $method = Request::method();
        $path = Request::path();

        $handler = $this->routes[$method][$path] ?? null;

        if ($handler === null) {
            Response::notFound();
        }

        call_user_func($handler);
    }
}