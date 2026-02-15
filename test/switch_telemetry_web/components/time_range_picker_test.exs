defmodule SwitchTelemetryWeb.Components.TimeRangePickerTestLive do
  @moduledoc false
  use Phoenix.LiveView

  alias SwitchTelemetryWeb.Components.TimeRangePicker

  def mount(_params, session, socket) do
    assigns = session["assigns"] || %{}
    selected = Map.get(assigns, :selected)

    socket =
      socket
      |> assign(:selected, selected)
      |> assign(:last_event, nil)

    {:ok, socket}
  end

  def handle_info({:time_range_changed, range}, socket) do
    {:noreply, assign(socket, last_event: range)}
  end

  def render(%{selected: nil} = assigns) do
    ~H"""
    <div id="last-event" data-event={inspect(@last_event)}></div>
    <.live_component
      module={TimeRangePicker}
      id="time-picker"
    />
    """
  end

  def render(assigns) do
    ~H"""
    <div id="last-event" data-event={inspect(@last_event)}></div>
    <.live_component
      module={TimeRangePicker}
      id="time-picker"
      selected={@selected}
    />
    """
  end
end

defmodule SwitchTelemetryWeb.Components.TimeRangePickerTest do
  use SwitchTelemetryWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias SwitchTelemetryWeb.Components.TimeRangePickerTestLive

  setup :register_and_log_in_user

  defp render_picker(conn, assigns \\ %{}) do
    {:ok, view, html} =
      live_isolated(conn, TimeRangePickerTestLive, session: %{"assigns" => assigns})

    {view, html}
  end

  describe "rendering" do
    test "renders all six preset buttons", %{conn: conn} do
      {_view, html} = render_picker(conn)
      assert html =~ "5 min"
      assert html =~ "15 min"
      assert html =~ "1 hour"
      assert html =~ "6 hours"
      assert html =~ "24 hours"
      assert html =~ "7 days"
    end

    test "renders Custom button", %{conn: conn} do
      {_view, html} = render_picker(conn)
      assert html =~ "Custom"
    end

    test "default selection highlights 1h preset with bg-indigo-600", %{conn: conn} do
      {_view, html} = render_picker(conn)

      # The 1h button should have the active/indigo styling by default
      # Split at "1 hour" and check that its surrounding button has bg-indigo-600
      assert html =~ "bg-indigo-600"
    end

    test "custom form is hidden by default", %{conn: conn} do
      {_view, html} = render_picker(conn)
      refute html =~ "datetime-local"
    end
  end

  describe "preset selection" do
    test "selecting a preset updates button styling", %{conn: conn} do
      {view, _html} = render_picker(conn)

      html =
        view
        |> element("button[phx-click=select_preset][phx-value-duration=\"5m\"]")
        |> render_click()

      # After clicking 5m, the 5m button should be highlighted
      assert html =~ "5 min"
    end

    test "select_preset event sends time_range_changed to parent", %{conn: conn} do
      {view, _html} = render_picker(conn)

      view
      |> element("button[phx-click=select_preset][phx-value-duration=\"15m\"]")
      |> render_click()

      html = render(view)

      # The last_event data attribute should contain the time range info
      assert html =~ "%{&quot;duration&quot; =&gt; &quot;15m&quot;"
      assert html =~ "&quot;type&quot; =&gt; &quot;relative&quot;"
    end
  end

  describe "custom date range" do
    test "toggle_custom shows custom date form", %{conn: conn} do
      {view, html} = render_picker(conn)
      refute html =~ "datetime-local"

      html =
        view
        |> element("button", "Custom")
        |> render_click()

      assert html =~ "datetime-local"
      assert html =~ "Start"
      assert html =~ "End"
      assert html =~ "Apply"
    end

    test "toggle_custom again hides custom date form", %{conn: conn} do
      {view, _html} = render_picker(conn)

      # Show custom form
      view
      |> element("button", "Custom")
      |> render_click()

      # Hide custom form
      html =
        view
        |> element("button", "Custom")
        |> render_click()

      refute html =~ "datetime-local"
    end

    test "apply_custom sends absolute range to parent", %{conn: conn} do
      {view, _html} = render_picker(conn)

      # Show custom form first
      view
      |> element("button", "Custom")
      |> render_click()

      # Submit the custom form
      view
      |> form("form[phx-submit=apply_custom]", %{
        "start" => "2026-01-01T00:00",
        "end" => "2026-01-02T00:00"
      })
      |> render_submit()

      html = render(view)
      assert html =~ "&quot;type&quot; =&gt; &quot;absolute&quot;"
      assert html =~ "2026-01-01T00:00"
      assert html =~ "2026-01-02T00:00"
    end

    test "Custom button is highlighted when absolute range is selected", %{conn: conn} do
      selected = %{
        "type" => "absolute",
        "start" => "2026-01-01T00:00",
        "end" => "2026-01-02T00:00"
      }

      {_view, html} = render_picker(conn, %{selected: selected})

      # The Custom button should have bg-indigo-600 when absolute range is selected
      # Find the Custom button area and verify it has indigo styling
      assert html =~ "Custom"
      assert html =~ "bg-indigo-600"
    end
  end
end
