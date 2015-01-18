defmodule Plug.CSRFProtectionTest do
  use ExUnit.Case, async: true
  use Plug.Test

  alias Plug.CSRFProtection
  alias Plug.CSRFProtection.InvalidCSRFTokenError
  alias Plug.CSRFProtection.InvalidCrossOriginRequestError

  @csrf_token "hello123"

  def call(conn, opts \\ [])

  def call(conn, opts) when is_list(opts) do
    conn
    |> fetch_params
    |> fetch_cookies
    |> CSRFProtection.call(opts)
    |> put_resp_content_type(conn.assigns[:content_type] || "text/html")
    |> send_resp(200, "ok")
  end

  def call(conn, old_conn) when is_map(old_conn) do
    call(conn, old_conn, [])
  end

  def call(conn, old_conn, opts) do
    conn
    |> recycle_cookies(old_conn)
    |> call(opts)
  end

  test "raise error for missing authenticity token in session" do
    assert_raise InvalidCSRFTokenError, fn ->
      conn(:post, "/") |> call()
    end

    assert_raise InvalidCSRFTokenError, fn ->
      conn(:post, "/", %{csrf_token: "foo"}) |> call()
    end
  end

  test "raise error for invalid authenticity token in params" do
    old_conn = call(conn(:get, "/"))

    assert_raise InvalidCSRFTokenError, fn ->
      conn(:post, "/", %{csrf_token: "foo"})
      |> call(old_conn)
    end

    assert_raise InvalidCSRFTokenError, fn ->
      conn(:post, "/", %{})
      |> call(old_conn)
    end
  end

  test "unprotected requests are always valid" do
    conn = conn(:get, "/") |> call()
    assert conn.halted == false
    assert conn.resp_cookies["_csrf_token"]

    conn = conn(:head, "/") |> call()
    assert conn.halted == false
    assert conn.resp_cookies["_csrf_token"]
  end

  test "protected requests with valid token in params are allowed" do
    old_conn = conn(:get, "/") |> call
    params = %{_csrf_token: old_conn.resp_cookies["_csrf_token"].value}

    conn = conn(:post, "/", params) |> call(old_conn)
    assert conn.halted == false

    conn = conn(:put, "/", params) |> call(old_conn)
    assert conn.halted == false

    conn = conn(:patch, "/", params) |> call(old_conn)
    assert conn.halted == false
  end

  test "protected requests with valid token in header are allowed" do
    old_conn   = conn(:get, "/") |> call
    csrf_token = old_conn.resp_cookies["_csrf_token"].value

    conn =
      conn(:post, "/")
      |> put_req_header("x-csrf-token", csrf_token)
      |> call(old_conn)
    assert conn.halted == false

    conn =
      conn(:put, "/")
      |> put_req_header("x-csrf-token", csrf_token)
      |> call(old_conn)
    assert conn.halted == false

    conn =
      conn(:patch, "/")
      |> put_req_header("x-csrf-token", csrf_token)
      |> call(old_conn)
    assert conn.halted == false
  end

  test "protected requests with valid token and custom name" do
    conn = conn(:get, "/") |> call(name: "SEKRET")
    assert conn.halted == false
    assert conn.resp_cookies["SEKRET"]

    params = %{_csrf_token: conn.resp_cookies["SEKRET"].value}
    conn = conn(:post, "/", params) |> call(conn, name: "SEKRET")
    assert conn.halted == false
  end

  test "non-XHR Javascript GET requests are forbidden" do
    assert_raise InvalidCrossOriginRequestError, fn ->
      conn(:get, "/") |> assign(:content_type, "application/javascript") |> call()
    end

    assert_raise InvalidCrossOriginRequestError, fn ->
      conn(:get, "/") |> assign(:content_type, "text/javascript") |> call()
    end
  end

  test "only XHR Javascript GET requests are allowed" do
    conn =
      conn(:get, "/")
      |> assign(:content_type, "text/javascript")
      |> put_req_header("x-requested-with", "XMLHttpRequest")
      |> call()
    assert conn.resp_cookies["_csrf_token"]
  end

  test "csrf plug is skipped when plug_skip_csrf_protection is true" do
    conn =
      conn(:get, "/")
      |> put_private(:plug_skip_csrf_protection, true)
      |> call()
    assert conn.resp_cookies["_csrf_token"]

    conn =
      conn(:post, "/", %{})
      |> put_private(:plug_skip_csrf_protection, true)
      |> call()
    assert conn.resp_cookies["_csrf_token"]

    conn =
      conn(:get, "/")
      |> put_private(:plug_skip_csrf_protection, true)
      |> assign(:content_type, "text/javascript")
      |> call()
    assert conn.resp_cookies["_csrf_token"]
  end
end
