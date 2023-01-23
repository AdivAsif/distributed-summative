defmodule MyAppWeb.PageController do
  use MyAppWeb, :controller

  def index(conn, _params) do
    render(conn, "index.html")
  end

  def test(conn, _params) do
    :ok
  end
end
