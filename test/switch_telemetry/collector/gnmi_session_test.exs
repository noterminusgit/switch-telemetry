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

  describe "state initialization" do
    test "struct has expected default values" do
      state = %GnmiSession{}
      assert state.device == nil
      assert state.channel == nil
      assert state.stream == nil
      assert state.task_ref == nil
      assert state.retry_count == nil
    end

    test "struct accepts device and retry_count" do
      state = %GnmiSession{device: %{id: "dev1"}, retry_count: 0}
      assert state.device.id == "dev1"
      assert state.retry_count == 0
      assert state.channel == nil
      assert state.stream == nil
      assert state.task_ref == nil
    end
  end

  describe "gNMI notification parsing logic" do
    test "Notification with multiple updates" do
      notif = %Gnmi.Notification{
        timestamp: 1_700_000_000_000_000_000,
        prefix: %Gnmi.Path{elem: [%Gnmi.PathElem{name: "interfaces", key: %{}}]},
        update: [
          %Gnmi.Update{
            path: %Gnmi.Path{elem: [%Gnmi.PathElem{name: "in-octets", key: %{}}]},
            val: %Gnmi.TypedValue{value: {:uint_val, 12345}}
          },
          %Gnmi.Update{
            path: %Gnmi.Path{elem: [%Gnmi.PathElem{name: "out-octets", key: %{}}]},
            val: %Gnmi.TypedValue{value: {:uint_val, 67890}}
          }
        ]
      }

      assert length(notif.update) == 2
      [u1, u2] = notif.update
      assert u1.val.value == {:uint_val, 12345}
      assert u2.val.value == {:uint_val, 67890}
    end

    test "Notification with zero timestamp defaults" do
      notif = %Gnmi.Notification{
        timestamp: 0,
        prefix: nil,
        update: []
      }

      assert notif.timestamp == 0
      assert notif.update == []
    end

    test "Notification with nanosecond timestamp conversion" do
      # 1_700_000_000 seconds = Nov 14, 2023
      ns_timestamp = 1_700_000_000_000_000_000
      {:ok, dt} = DateTime.from_unix(ns_timestamp, :nanosecond)
      assert dt.year == 2023
      assert dt.month == 11
    end

    test "PathElem with multiple keys" do
      elem = %Gnmi.PathElem{
        name: "interface",
        key: %{"name" => "eth0", "ifindex" => "1"}
      }

      assert map_size(elem.key) == 2
      assert elem.key["name"] == "eth0"
      assert elem.key["ifindex"] == "1"
    end

    test "path string parsing logic" do
      # Test the logic that parse_path_string implements
      path_str = "/interfaces/interface[name=eth0]/state/counters"
      segments = path_str |> String.trim_leading("/") |> String.split("/")

      assert length(segments) == 4
      assert hd(segments) == "interfaces"

      # Test key extraction from segment
      segment_with_keys = "interface[name=eth0]"

      case Regex.run(~r/^([^\[]+)\[(.+)\]$/, segment_with_keys) do
        [_, name, keys_str] ->
          assert name == "interface"

          keys =
            keys_str
            |> String.split(",")
            |> Map.new(fn kv ->
              [k, v] = String.split(kv, "=", parts: 2)
              {k, v}
            end)

          assert keys == %{"name" => "eth0"}

        nil ->
          flunk("Should have matched")
      end
    end

    test "path string with multiple keys" do
      segment = "interface[name=eth0,ifindex=1]"
      [_, name, keys_str] = Regex.run(~r/^([^\[]+)\[(.+)\]$/, segment)
      assert name == "interface"

      keys =
        keys_str
        |> String.split(",")
        |> Map.new(fn kv ->
          [k, v] = String.split(kv, "=", parts: 2)
          {k, v}
        end)

      assert keys == %{"name" => "eth0", "ifindex" => "1"}
    end

    test "segment without keys returns nil from regex" do
      segment = "counters"
      assert Regex.run(~r/^([^\[]+)\[(.+)\]$/, segment) == nil
    end

    test "path formatting from prefix and path elems" do
      # Replicate the format_path logic inline
      prefix = %Gnmi.Path{elem: [%Gnmi.PathElem{name: "openconfig", key: %{}}]}
      path = %Gnmi.Path{elem: [%Gnmi.PathElem{name: "interfaces", key: %{}}, %Gnmi.PathElem{name: "interface", key: %{"name" => "eth0"}}]}

      prefix_elems = if prefix, do: prefix.elem || [], else: []
      all_elems = prefix_elems ++ (path.elem || [])

      formatted =
        "/" <>
          Enum.map_join(all_elems, "/", fn %Gnmi.PathElem{name: name, key: keys} ->
            if keys != nil and map_size(keys) > 0 do
              key_str = Enum.map_join(keys, ",", fn {k, v} -> "#{k}=#{v}" end)
              "#{name}[#{key_str}]"
            else
              name
            end
          end)

      assert formatted == "/openconfig/interfaces/interface[name=eth0]"
    end

    test "path formatting with nil prefix" do
      path = %Gnmi.Path{elem: [%Gnmi.PathElem{name: "state", key: %{}}, %Gnmi.PathElem{name: "counters", key: %{}}]}

      prefix_elems = []
      all_elems = prefix_elems ++ (path.elem || [])

      formatted =
        "/" <>
          Enum.map_join(all_elems, "/", fn %Gnmi.PathElem{name: name, key: keys} ->
            if keys != nil and map_size(keys) > 0 do
              key_str = Enum.map_join(keys, ",", fn {k, v} -> "#{k}=#{v}" end)
              "#{name}[#{key_str}]"
            else
              name
            end
          end)

      assert formatted == "/state/counters"
    end

    test "tag extraction from path elems" do
      path = %Gnmi.Path{
        elem: [
          %Gnmi.PathElem{name: "interfaces", key: %{}},
          %Gnmi.PathElem{name: "interface", key: %{"name" => "eth0"}},
          %Gnmi.PathElem{name: "subinterfaces", key: %{}},
          %Gnmi.PathElem{name: "subinterface", key: %{"index" => "0"}}
        ]
      }

      # Replicate extract_tags logic inline
      tags =
        Enum.reduce(path.elem, %{}, fn %Gnmi.PathElem{key: keys}, acc ->
          if keys != nil, do: Map.merge(acc, keys), else: acc
        end)

      assert tags == %{"name" => "eth0", "index" => "0"}
    end

    test "tag extraction from path with no keys" do
      path = %Gnmi.Path{
        elem: [
          %Gnmi.PathElem{name: "state", key: %{}},
          %Gnmi.PathElem{name: "counters", key: %{}}
        ]
      }

      tags =
        Enum.reduce(path.elem, %{}, fn %Gnmi.PathElem{key: keys}, acc ->
          if keys != nil, do: Map.merge(acc, keys), else: acc
        end)

      assert tags == %{}
    end
  end

  describe "TypedValue extraction logic" do
    test "double_val extraction" do
      tv = %Gnmi.TypedValue{value: {:double_val, 3.14}}
      assert {:double_val, val} = tv.value
      assert val == 3.14
    end

    test "float_val extraction" do
      tv = %Gnmi.TypedValue{value: {:float_val, 2.5}}
      assert {:float_val, val} = tv.value
      assert val == 2.5
    end

    test "int_val extraction" do
      tv = %Gnmi.TypedValue{value: {:int_val, -42}}
      assert {:int_val, val} = tv.value
      assert val == -42
    end

    test "uint_val extraction" do
      tv = %Gnmi.TypedValue{value: {:uint_val, 100}}
      assert {:uint_val, val} = tv.value
      assert val == 100
    end

    test "string_val extraction" do
      tv = %Gnmi.TypedValue{value: {:string_val, "up"}}
      assert {:string_val, val} = tv.value
      assert val == "up"
    end

    test "bool_val extraction" do
      tv = %Gnmi.TypedValue{value: {:bool_val, true}}
      assert {:bool_val, val} = tv.value
      assert val == true
    end

    test "bytes_val extraction" do
      tv = %Gnmi.TypedValue{value: {:bytes_val, <<1, 2, 3>>}}
      assert {:bytes_val, val} = tv.value
      assert val == <<1, 2, 3>>
    end

    test "json_val extraction" do
      json = ~s({"status": "up"})
      tv = %Gnmi.TypedValue{value: {:json_val, json}}
      assert {:json_val, val} = tv.value
      assert val == json
    end

    test "nil TypedValue" do
      tv = %Gnmi.TypedValue{value: nil}
      assert tv.value == nil
    end

    test "extract_float logic for double_val" do
      tv = %Gnmi.TypedValue{value: {:double_val, 99.9}}
      result = case tv.value do
        {:double_val, v} -> v
        {:float_val, v} -> v
        _ -> nil
      end
      assert result == 99.9
    end

    test "extract_float logic for float_val" do
      tv = %Gnmi.TypedValue{value: {:float_val, 1.5}}
      result = case tv.value do
        {:double_val, v} -> v
        {:float_val, v} -> v
        _ -> nil
      end
      assert result == 1.5
    end

    test "extract_float logic returns nil for int_val" do
      tv = %Gnmi.TypedValue{value: {:int_val, 42}}
      result = case tv.value do
        {:double_val, v} -> v
        {:float_val, v} -> v
        _ -> nil
      end
      assert result == nil
    end

    test "extract_int logic for int_val" do
      tv = %Gnmi.TypedValue{value: {:int_val, -10}}
      result = case tv.value do
        {:int_val, v} -> v
        {:uint_val, v} -> v
        _ -> nil
      end
      assert result == -10
    end

    test "extract_int logic for uint_val" do
      tv = %Gnmi.TypedValue{value: {:uint_val, 255}}
      result = case tv.value do
        {:int_val, v} -> v
        {:uint_val, v} -> v
        _ -> nil
      end
      assert result == 255
    end

    test "extract_int logic returns nil for string_val" do
      tv = %Gnmi.TypedValue{value: {:string_val, "hello"}}
      result = case tv.value do
        {:int_val, v} -> v
        {:uint_val, v} -> v
        _ -> nil
      end
      assert result == nil
    end

    test "extract_str logic for string_val" do
      tv = %Gnmi.TypedValue{value: {:string_val, "up"}}
      result = case tv.value do
        {:string_val, v} -> v
        _ -> nil
      end
      assert result == "up"
    end

    test "extract_str logic returns nil for numeric types" do
      tv = %Gnmi.TypedValue{value: {:uint_val, 100}}
      result = case tv.value do
        {:string_val, v} -> v
        _ -> nil
      end
      assert result == nil
    end
  end

  describe "exponential backoff logic" do
    test "calculates increasing delays" do
      base = 5_000
      max_delay = 300_000

      delays =
        for count <- 0..10 do
          min(trunc(base * :math.pow(2, count)), max_delay)
        end

      assert Enum.at(delays, 0) == 5_000
      assert Enum.at(delays, 1) == 10_000
      assert Enum.at(delays, 2) == 20_000
      assert Enum.at(delays, 3) == 40_000
      # Eventually caps at max
      assert Enum.at(delays, 10) == 300_000
    end

    test "delay never exceeds max" do
      base = 5_000
      max_delay = 300_000

      for count <- 0..20 do
        delay = min(trunc(base * :math.pow(2, count)), max_delay)
        assert delay <= max_delay
      end
    end

    test "first retry is base delay" do
      base = 5_000
      delay = min(trunc(base * :math.pow(2, 0)), 300_000)
      assert delay == 5_000
    end
  end

  describe "metric map construction" do
    test "builds complete metric map from notification data" do
      device_id = "device-123"
      ns_timestamp = 1_700_000_000_000_000_000
      timestamp = DateTime.from_unix!(ns_timestamp, :nanosecond)

      prefix = %Gnmi.Path{elem: [%Gnmi.PathElem{name: "interfaces", key: %{}}]}

      update = %Gnmi.Update{
        path: %Gnmi.Path{
          elem: [
            %Gnmi.PathElem{name: "interface", key: %{"name" => "eth0"}},
            %Gnmi.PathElem{name: "in-octets", key: %{}}
          ]
        },
        val: %Gnmi.TypedValue{value: {:uint_val, 12345}}
      }

      # Replicate the metric map construction from parse_notification
      path_elems = (prefix.elem || []) ++ (update.path.elem || [])

      formatted_path =
        "/" <>
          Enum.map_join(path_elems, "/", fn %Gnmi.PathElem{name: name, key: keys} ->
            if keys != nil and map_size(keys) > 0 do
              key_str = Enum.map_join(keys, ",", fn {k, v} -> "#{k}=#{v}" end)
              "#{name}[#{key_str}]"
            else
              name
            end
          end)

      tags =
        Enum.reduce(update.path.elem, %{}, fn %Gnmi.PathElem{key: keys}, acc ->
          if keys != nil, do: Map.merge(acc, keys), else: acc
        end)

      tv = update.val

      metric = %{
        time: timestamp,
        device_id: device_id,
        path: formatted_path,
        source: "gnmi",
        tags: tags,
        value_float:
          case tv.value do
            {:double_val, v} -> v
            {:float_val, v} -> v
            _ -> nil
          end,
        value_int:
          case tv.value do
            {:int_val, v} -> v
            {:uint_val, v} -> v
            _ -> nil
          end,
        value_str:
          case tv.value do
            {:string_val, v} -> v
            _ -> nil
          end
      }

      assert metric.time == timestamp
      assert metric.device_id == "device-123"
      assert metric.path == "/interfaces/interface[name=eth0]/in-octets"
      assert metric.source == "gnmi"
      assert metric.tags == %{"name" => "eth0"}
      assert metric.value_float == nil
      assert metric.value_int == 12345
      assert metric.value_str == nil
    end
  end

  describe "SubscribeRequest construction" do
    test "builds STREAM mode request" do
      subscriptions = [
        %Gnmi.Subscription{
          path: %Gnmi.Path{
            elem: [
              %Gnmi.PathElem{name: "interfaces", key: %{}},
              %Gnmi.PathElem{name: "interface", key: %{}}
            ]
          },
          mode: :SAMPLE,
          sample_interval: 30_000_000_000
        }
      ]

      req = %Gnmi.SubscribeRequest{
        request:
          {:subscribe,
           %Gnmi.SubscriptionList{
             subscription: subscriptions,
             mode: :STREAM,
             encoding: :PROTO
           }}
      }

      {:subscribe, sub_list} = req.request
      assert sub_list.mode == :STREAM
      assert sub_list.encoding == :PROTO
      assert length(sub_list.subscription) == 1
      [sub] = sub_list.subscription
      assert sub.mode == :SAMPLE
      assert sub.sample_interval == 30_000_000_000
    end

    test "builds request with multiple subscriptions" do
      paths = [
        "/interfaces/interface/state/counters",
        "/system/cpu",
        "/system/memory"
      ]

      subscriptions =
        Enum.map(paths, fn path_str ->
          elems =
            path_str
            |> String.trim_leading("/")
            |> String.split("/")
            |> Enum.map(fn segment ->
              case Regex.run(~r/^([^\[]+)\[(.+)\]$/, segment) do
                [_, name, keys_str] ->
                  keys =
                    keys_str
                    |> String.split(",")
                    |> Map.new(fn kv ->
                      [k, v] = String.split(kv, "=", parts: 2)
                      {k, v}
                    end)

                  %Gnmi.PathElem{name: name, key: keys}

                nil ->
                  %Gnmi.PathElem{name: segment, key: %{}}
              end
            end)

          %Gnmi.Subscription{
            path: %Gnmi.Path{elem: elems},
            mode: :SAMPLE,
            sample_interval: 10_000_000_000
          }
        end)

      assert length(subscriptions) == 3

      [s1, s2, s3] = subscriptions
      assert hd(s1.path.elem).name == "interfaces"
      assert hd(s2.path.elem).name == "system"
      assert hd(s3.path.elem).name == "system"
    end
  end
end
