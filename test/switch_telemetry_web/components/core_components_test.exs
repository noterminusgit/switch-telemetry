defmodule SwitchTelemetryWeb.CoreComponentsTest do
  use SwitchTelemetryWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import SwitchTelemetryWeb.CoreComponents

  describe "status_badge/1" do
    test "renders active badge with green styling" do
      html = render_component(&status_badge/1, %{status: :active})
      assert html =~ "Active"
      assert html =~ "green"
    end

    test "renders inactive badge with gray styling" do
      html = render_component(&status_badge/1, %{status: :inactive})
      assert html =~ "Inactive"
      assert html =~ "gray"
    end

    test "renders unreachable badge with red styling" do
      html = render_component(&status_badge/1, %{status: :unreachable})
      assert html =~ "Unreachable"
      assert html =~ "red"
    end

    test "renders maintenance badge with yellow styling" do
      html = render_component(&status_badge/1, %{status: :maintenance})
      assert html =~ "Maintenance"
      assert html =~ "yellow"
    end

    test "renders with custom class" do
      html = render_component(&status_badge/1, %{status: :active, class: "extra-class"})
      assert html =~ "extra-class"
      assert html =~ "Active"
    end

    test "renders an SVG circle indicator" do
      html = render_component(&status_badge/1, %{status: :active})
      assert html =~ "<svg"
      assert html =~ "<circle"
      assert html =~ "viewBox"
    end

    test "renders as a span element with badge classes" do
      html = render_component(&status_badge/1, %{status: :active})
      assert html =~ "inline-flex"
      assert html =~ "rounded-full"
      assert html =~ "text-xs"
      assert html =~ "font-medium"
    end
  end

  describe "flash/1" do
    test "renders info flash with emerald styling" do
      html = render_component(&flash/1, %{kind: :info, flash: %{"info" => "Success message"}})
      assert html =~ "Success message"
      assert html =~ "emerald"
    end

    test "renders error flash with rose styling" do
      html = render_component(&flash/1, %{kind: :error, flash: %{"error" => "Error message"}})
      assert html =~ "Error message"
      assert html =~ "rose"
    end

    test "does not render when flash is empty" do
      html = render_component(&flash/1, %{kind: :info, flash: %{}})
      refute html =~ "role=\"alert\""
    end

    test "renders with title when provided" do
      html =
        render_component(&flash/1, %{
          kind: :info,
          title: "Notice",
          flash: %{"info" => "Details here"}
        })

      assert html =~ "Notice"
      assert html =~ "Details here"
    end

    test "generates default id from kind" do
      html = render_component(&flash/1, %{kind: :info, flash: %{"info" => "test"}})
      assert html =~ "flash-info"
    end

    test "uses custom id when provided" do
      html =
        render_component(&flash/1, %{id: "custom-flash", kind: :error, flash: %{"error" => "msg"}})

      assert html =~ "custom-flash"
    end

    test "renders with role alert attribute" do
      html = render_component(&flash/1, %{kind: :info, flash: %{"info" => "test"}})
      assert html =~ ~s(role="alert")
    end
  end

  describe "flash_group/1" do
    test "renders info and error flash containers" do
      html = render_component(&flash_group/1, %{flash: %{}})
      assert html =~ "flash-group"
    end

    test "renders with custom id" do
      html = render_component(&flash_group/1, %{flash: %{}, id: "my-flashes"})
      assert html =~ "my-flashes"
    end
  end

  describe "icon/1" do
    test "renders a heroicon span with the icon name as class" do
      html = render_component(&icon/1, %{name: "hero-x-mark-solid"})
      assert html =~ "hero-x-mark-solid"
      assert html =~ "<span"
    end

    test "renders with additional classes" do
      html = render_component(&icon/1, %{name: "hero-arrow-path", class: "ml-1 w-3 h-3"})
      assert html =~ "hero-arrow-path"
      assert html =~ "ml-1"
      assert html =~ "w-3"
      assert html =~ "h-3"
    end

    test "renders without extra class" do
      html = render_component(&icon/1, %{name: "hero-check"})
      assert html =~ "hero-check"
    end
  end

  describe "input/1 (text type)" do
    test "renders a text input" do
      html = render_component(&input/1, %{name: "username", type: "text", errors: []})
      assert html =~ ~s(type="text")
      assert html =~ ~s(name="username")
    end

    test "renders with label" do
      html =
        render_component(&input/1, %{
          name: "email",
          type: "email",
          label: "Email Address",
          errors: []
        })

      assert html =~ "Email Address"
      assert html =~ "<label"
    end

    test "renders without label when not provided" do
      html = render_component(&input/1, %{name: "email", type: "text", errors: []})
      refute html =~ "<label"
    end

    test "renders with an id" do
      html =
        render_component(&input/1, %{id: "my-input", name: "field", type: "text", errors: []})

      assert html =~ ~s(id="my-input")
    end

    test "renders error messages" do
      html =
        render_component(&input/1, %{
          name: "email",
          type: "text",
          errors: ["can't be blank", "is invalid"]
        })

      assert html =~ "can&#39;t be blank"
      assert html =~ "is invalid"
      assert html =~ "text-red-600"
    end

    test "renders with value" do
      html =
        render_component(&input/1, %{
          name: "name",
          type: "text",
          value: "John",
          errors: []
        })

      assert html =~ ~s(value="John")
    end
  end

  describe "input/1 (select type)" do
    test "renders a select element" do
      html =
        render_component(&input/1, %{
          name: "role",
          type: "select",
          options: [{"Admin", "admin"}, {"Viewer", "viewer"}],
          errors: []
        })

      assert html =~ "<select"
      assert html =~ "Admin"
      assert html =~ "Viewer"
    end

    test "renders select with prompt" do
      html =
        render_component(&input/1, %{
          name: "role",
          type: "select",
          options: [{"Admin", "admin"}],
          prompt: "Choose a role",
          errors: []
        })

      assert html =~ "Choose a role"
    end

    test "renders select with label" do
      html =
        render_component(&input/1, %{
          name: "role",
          type: "select",
          label: "User Role",
          options: [{"Admin", "admin"}],
          errors: []
        })

      assert html =~ "User Role"
    end
  end

  describe "input/1 (textarea type)" do
    test "renders a textarea element" do
      html =
        render_component(&input/1, %{
          name: "description",
          type: "textarea",
          errors: []
        })

      assert html =~ "<textarea"
      assert html =~ ~s(name="description")
    end

    test "renders textarea with label" do
      html =
        render_component(&input/1, %{
          name: "notes",
          type: "textarea",
          label: "Notes",
          errors: []
        })

      assert html =~ "Notes"
      assert html =~ "<label"
    end
  end

  describe "button/1" do
    test "renders a button with indigo styling" do
      html =
        render_component(&button/1, %{
          inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "Click Me" end}]
        })

      assert html =~ "Click Me"
      assert html =~ "bg-indigo-600"
      assert html =~ "<button"
    end

    test "renders with custom class" do
      html =
        render_component(&button/1, %{
          class: "ml-4",
          inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "Save" end}]
        })

      assert html =~ "ml-4"
      assert html =~ "Save"
    end

    test "renders with type attribute" do
      html =
        render_component(&button/1, %{
          type: "submit",
          inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "Submit" end}]
        })

      assert html =~ ~s(type="submit")
    end
  end

  describe "header/1" do
    test "renders header text in h1 tag" do
      html =
        render_component(&header/1, %{
          inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "Page Title" end}]
        })

      assert html =~ "<header"
      assert html =~ "<h1"
      assert html =~ "Page Title"
    end

    test "renders with custom class" do
      html =
        render_component(&header/1, %{
          class: "mb-8",
          inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "Title" end}]
        })

      assert html =~ "mb-8"
    end
  end

  describe "modal/1" do
    test "renders modal with id" do
      html =
        render_component(&modal/1, %{
          id: "test-modal",
          inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "Modal content" end}]
        })

      assert html =~ "test-modal"
      assert html =~ "Modal content"
      assert html =~ ~s(role="dialog")
      assert html =~ ~s(aria-modal="true")
    end

    test "renders modal with hidden class by default" do
      html =
        render_component(&modal/1, %{
          id: "hidden-modal",
          inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "Content" end}]
        })

      assert html =~ "hidden"
    end

    test "renders close button with sr-only text" do
      html =
        render_component(&modal/1, %{
          id: "close-modal",
          inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "Content" end}]
        })

      assert html =~ "Close panel"
      assert html =~ "sr-only"
    end
  end

  describe "tabs/1" do
    test "renders tab navigation" do
      html =
        render_component(&tabs/1, %{
          id: "device-tabs",
          active_tab: "overview",
          tab: [
            %{__slot__: :tab, id: "overview", label: "Overview"},
            %{__slot__: :tab, id: "metrics", label: "Metrics"}
          ]
        })

      assert html =~ "Overview"
      assert html =~ "Metrics"
      assert html =~ "device-tabs"
    end

    test "highlights the active tab" do
      html =
        render_component(&tabs/1, %{
          id: "my-tabs",
          active_tab: "overview",
          tab: [
            %{__slot__: :tab, id: "overview", label: "Overview"},
            %{__slot__: :tab, id: "metrics", label: "Metrics"}
          ]
        })

      assert html =~ "border-indigo-500"
      assert html =~ ~s(aria-current="page")
    end

    test "does not highlight inactive tabs" do
      html =
        render_component(&tabs/1, %{
          id: "my-tabs",
          active_tab: "overview",
          tab: [
            %{__slot__: :tab, id: "overview", label: "Overview"},
            %{__slot__: :tab, id: "metrics", label: "Metrics"}
          ]
        })

      assert html =~ "border-transparent"
    end
  end

  describe "dropdown/1" do
    test "renders dropdown with id" do
      html =
        render_component(&dropdown/1, %{
          id: "user-menu",
          trigger: [%{__slot__: :trigger, inner_block: fn _, _ -> "Options" end}],
          item: []
        })

      assert html =~ "user-menu"
      assert html =~ "Options"
    end

    test "renders dropdown menu container" do
      html =
        render_component(&dropdown/1, %{
          id: "dd-test",
          trigger: [%{__slot__: :trigger, inner_block: fn _, _ -> "Menu" end}],
          item: []
        })

      assert html =~ "dd-test-menu"
      assert html =~ ~s(role="menu")
    end
  end
end
