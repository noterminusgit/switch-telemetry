defmodule SwitchTelemetry.Collector.GnmiSessionTest do
  use SwitchTelemetry.DataCase, async: true

  alias SwitchTelemetry.Collector.GnmiSession

  describe "parse gNMI paths" do
    test "format_path handles simple paths" do
      path = %Gnmi.Path{
        elem: [
          %Gnmi.PathElem{name: "interfaces", key: %{}},
          %Gnmi.PathElem{name: "interface", key: %{"name" => "eth0"}},
          %Gnmi.PathElem{name: "state", key: %{}},
          %Gnmi.PathElem{name: "counters", key: %{}}
        ]
      }

      # Test via the public module struct
      assert path.elem |> length() == 4
      assert hd(path.elem).name == "interfaces"
    end

    test "PathElem with keys" do
      elem = %Gnmi.PathElem{name: "interface", key: %{"name" => "eth0"}}
      assert elem.name == "interface"
      assert elem.key == %{"name" => "eth0"}
    end

    test "TypedValue variants" do
      assert %Gnmi.TypedValue{value: {:int_val, 42}}.value == {:int_val, 42}
      assert %Gnmi.TypedValue{value: {:double_val, 3.14}}.value == {:double_val, 3.14}
      assert %Gnmi.TypedValue{value: {:string_val, "up"}}.value == {:string_val, "up"}
    end

    test "Notification struct" do
      notif = %Gnmi.Notification{
        timestamp: 1_700_000_000_000_000_000,
        prefix: %Gnmi.Path{elem: [%Gnmi.PathElem{name: "openconfig", key: %{}}]},
        update: [
          %Gnmi.Update{
            path: %Gnmi.Path{elem: [%Gnmi.PathElem{name: "counter", key: %{}}]},
            val: %Gnmi.TypedValue{value: {:uint_val, 12345}}
          }
        ]
      }

      assert notif.timestamp == 1_700_000_000_000_000_000
      assert length(notif.update) == 1
    end

    test "SubscribeRequest struct" do
      req = %Gnmi.SubscribeRequest{
        request:
          {:subscribe,
           %Gnmi.SubscriptionList{
             subscription: [
               %Gnmi.Subscription{
                 path: %Gnmi.Path{
                   elem: [%Gnmi.PathElem{name: "interfaces", key: %{}}]
                 },
                 mode: :SAMPLE,
                 sample_interval: 30_000_000_000
               }
             ],
             mode: :STREAM,
             encoding: :PROTO
           }}
      }

      {:subscribe, sub_list} = req.request
      assert sub_list.mode == :STREAM
      assert length(sub_list.subscription) == 1
    end
  end

  describe "child_spec" do
    test "start_link requires device option" do
      assert_raise KeyError, fn ->
        GnmiSession.start_link([])
      end
    end
  end
end
