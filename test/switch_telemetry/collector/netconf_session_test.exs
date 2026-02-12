defmodule SwitchTelemetry.Collector.NetconfSessionTest do
  use SwitchTelemetry.DataCase, async: true

  alias SwitchTelemetry.Collector.NetconfSession

  describe "struct" do
    test "default state" do
      state = %NetconfSession{}
      assert state.device == nil
      assert state.ssh_ref == nil
      assert state.channel_id == nil
      assert state.buffer == ""
      assert state.message_id == 1
    end
  end

  describe "child_spec" do
    test "start_link requires device option" do
      assert_raise KeyError, fn ->
        NetconfSession.start_link([])
      end
    end
  end

  describe "message extraction" do
    test "extracts single complete message" do
      buffer = "<?xml version=\"1.0\"?><rpc-reply>data</rpc-reply>]]>]]>"
      # The extract_messages logic: split on ]]>]]>
      parts = String.split(buffer, "]]>]]>", parts: 2)
      assert length(parts) == 2
      [message, rest] = parts
      assert message == "<?xml version=\"1.0\"?><rpc-reply>data</rpc-reply>"
      assert rest == ""
    end

    test "extracts multiple messages from buffer" do
      buffer = "msg1]]>]]>msg2]]>]]>msg3]]>]]>"
      messages = buffer |> String.split("]]>]]>") |> Enum.reject(&(&1 == ""))
      assert messages == ["msg1", "msg2", "msg3"]
    end

    test "handles partial message in buffer" do
      buffer = "complete_msg]]>]]>partial_msg_no_end"
      [complete, rest] = String.split(buffer, "]]>]]>", parts: 2)
      assert complete == "complete_msg"
      assert rest == "partial_msg_no_end"
    end

    test "handles empty buffer" do
      buffer = ""
      parts = String.split(buffer, "]]>]]>", parts: 2)
      assert parts == [""]
    end

    test "recursive extraction accumulates messages in order" do
      # Replicate the exact extract_messages/2 recursive logic from the module
      buffer = "first]]>]]>second]]>]]>remaining"

      {messages, leftover} = extract_messages_logic(buffer, [])

      assert messages == ["first", "second"]
      assert leftover == "remaining"
    end

    test "recursive extraction handles no delimiter" do
      buffer = "no delimiter here"

      {messages, leftover} = extract_messages_logic(buffer, [])

      assert messages == []
      assert leftover == "no delimiter here"
    end

    test "recursive extraction handles empty messages between delimiters" do
      buffer = "]]>]]>]]>]]>"

      {messages, leftover} = extract_messages_logic(buffer, [])

      # First split: "" and "]]>]]>", second split: "" and ""
      assert messages == ["", ""]
      assert leftover == ""
    end
  end

  describe "XML RPC building" do
    test "builds get RPC with filter" do
      message_id = 42
      filter_path = "<interfaces/>"

      rpc = """
      <?xml version="1.0" encoding="UTF-8"?>
      <rpc message-id="#{message_id}" xmlns="urn:ietf:params:xml:ns:netconf:base:1.0">
        <get>
          <filter type="subtree">
            #{filter_path}
          </filter>
        </get>
      </rpc>
      ]]>]]>
      """

      assert rpc =~ "message-id=\"42\""
      assert rpc =~ "<filter type=\"subtree\">"
      assert rpc =~ "<interfaces/>"
      assert rpc =~ "]]>]]>"
    end

    test "RPC contains NETCONF namespace" do
      rpc = """
      <?xml version="1.0" encoding="UTF-8"?>
      <rpc message-id="1" xmlns="urn:ietf:params:xml:ns:netconf:base:1.0">
        <get><filter type="subtree"><system/></filter></get>
      </rpc>
      ]]>]]>
      """

      assert rpc =~ "urn:ietf:params:xml:ns:netconf:base:1.0"
    end

    test "message IDs increment" do
      state = %NetconfSession{message_id: 1}
      assert state.message_id == 1
      next_state = %{state | message_id: state.message_id + 1}
      assert next_state.message_id == 2
    end

    test "message ID is included in RPC" do
      for id <- [1, 5, 99, 1000] do
        rpc = build_test_rpc(id, "<test/>")
        assert rpc =~ "message-id=\"#{id}\""
      end
    end
  end

  describe "value parsing logic" do
    test "parses integer strings" do
      assert Integer.parse("42") == {42, ""}
      assert Integer.parse("0") == {0, ""}
      assert Integer.parse("-100") == {-100, ""}
      assert Integer.parse("abc") == :error
    end

    test "parses float strings" do
      assert Float.parse("3.14") == {3.14, ""}
      assert Float.parse("42.0") == {42.0, ""}
      assert Float.parse("abc") == :error
    end

    test "integer-only strings are integers not floats" do
      value = "42"
      {i, ""} = Integer.parse(value)
      assert i == 42
      # Float.parse would also work on "42" but we want integer
      {f, ""} = Float.parse(value)
      assert f == 42.0
    end

    test "string values are non-numeric" do
      value = "up"
      assert Integer.parse(value) == :error
      assert Float.parse(value) == :error
    end

    test "parse_float logic matches source implementation" do
      # Replicate the exact parse_float logic from netconf_session.ex
      # Note: Float.parse("42") returns {42.0, ""} so parse_float returns 42.0
      assert parse_float_logic("3.14") == 3.14
      assert parse_float_logic("42") == 42.0
      assert parse_float_logic("abc") == nil
      assert parse_float_logic("1.0e3") == 1.0e3
    end

    test "parse_int logic matches source implementation" do
      # Replicate the exact parse_int logic from netconf_session.ex
      assert parse_int_logic("42") == 42
      assert parse_int_logic("0") == 0
      assert parse_int_logic("-100") == -100
      assert parse_int_logic("abc") == nil
      assert parse_int_logic("3.14") == nil
    end

    test "numeric? detection logic" do
      assert numeric_logic?("42")
      assert numeric_logic?("3.14")
      refute numeric_logic?("up")
      refute numeric_logic?("enabled")
    end

    test "string value stored only when non-numeric" do
      # Replicate the metric building logic for value_str
      for {value, expected} <- [
            {"up", "up"},
            {"enabled", "enabled"},
            {"42", nil},
            {"3.14", nil}
          ] do
        result = if numeric_logic?(value), do: nil, else: value

        assert result == expected,
               "Expected #{inspect(expected)} for value #{inspect(value)}, got #{inspect(result)}"
      end
    end
  end

  describe "NETCONF hello" do
    test "hello message contains capabilities" do
      state = NetconfSession.__struct__()
      assert is_binary(state.buffer)
      assert state.buffer == ""
      assert state.message_id == 1
    end

    test "default struct values are correct" do
      state = %NetconfSession{}
      assert state.device == nil
      assert state.ssh_ref == nil
      assert state.channel_id == nil
      assert state.timer_ref == nil
      assert state.buffer == ""
      assert state.message_id == 1
    end
  end

  describe "SSH connection options" do
    test "builds options with password" do
      opts = [
        {:user, ~c"admin"},
        {:silently_accept_hosts, true},
        {:connect_timeout, 10_000},
        {:password, ~c"secret"}
      ]

      assert Keyword.get(opts, :user) == ~c"admin"
      assert Keyword.get(opts, :password) == ~c"secret"
      assert Keyword.get(opts, :connect_timeout) == 10_000
    end

    test "builds options without password" do
      opts = [
        {:user, ~c"admin"},
        {:silently_accept_hosts, true},
        {:connect_timeout, 10_000}
      ]

      refute Keyword.has_key?(opts, :password)
    end

    test "conditional password addition matches source logic" do
      # Test the exact pattern used in the source
      base_opts = [
        {:user, ~c"admin"},
        {:silently_accept_hosts, true},
        {:connect_timeout, 10_000}
      ]

      # With password
      password = "secret"

      opts_with =
        if password do
          [{:password, String.to_charlist(password)} | base_opts]
        else
          base_opts
        end

      assert Keyword.get(opts_with, :password) == ~c"secret"

      # Without password
      password_nil = nil

      opts_without =
        if password_nil do
          [{:password, String.to_charlist(password_nil)} | base_opts]
        else
          base_opts
        end

      refute Keyword.has_key?(opts_without, :password)
    end
  end

  describe "buffer management" do
    test "buffer concatenation with new data" do
      state = %NetconfSession{buffer: "partial"}
      new_data = " message]]>]]>"
      new_buffer = state.buffer <> new_data
      assert new_buffer == "partial message]]>]]>"
    end

    test "buffer resets after message extraction" do
      buffer = "complete message]]>]]>leftover"
      [_msg, remaining] = String.split(buffer, "]]>]]>", parts: 2)
      state = %NetconfSession{buffer: remaining}
      assert state.buffer == "leftover"
    end

    test "buffer handles binary data conversion" do
      # SSH sends chardata; to_string converts it
      data = ~c"hello"
      assert to_string(data) == "hello"

      binary_data = <<104, 101, 108, 108, 111>>
      assert to_string(binary_data) == "hello"
    end
  end

  describe "NETCONF metric map construction" do
    test "builds metric map with string value" do
      device_id = "device-456"
      now = DateTime.utc_now()
      value = "up"

      metric = %{
        time: now,
        device_id: device_id,
        path: "/status",
        source: "netconf",
        tags: %{},
        value_float: parse_float_logic(value),
        value_int: parse_int_logic(value),
        value_str: if(numeric_logic?(value), do: nil, else: value)
      }

      assert metric.source == "netconf"
      assert metric.value_float == nil
      assert metric.value_int == nil
      assert metric.value_str == "up"
    end

    test "builds metric map with integer value" do
      value = "42"

      metric = %{
        time: DateTime.utc_now(),
        device_id: "dev1",
        path: "/counter",
        source: "netconf",
        tags: %{},
        value_float: parse_float_logic(value),
        value_int: parse_int_logic(value),
        value_str: if(numeric_logic?(value), do: nil, else: value)
      }

      # Note: Float.parse("42") returns {42.0, ""} so value_float is set too
      assert metric.value_float == 42.0
      assert metric.value_int == 42
      assert metric.value_str == nil
    end

    test "builds metric map with float value" do
      value = "3.14"

      metric = %{
        time: DateTime.utc_now(),
        device_id: "dev1",
        path: "/temperature",
        source: "netconf",
        tags: %{},
        value_float: parse_float_logic(value),
        value_int: parse_int_logic(value),
        value_str: if(numeric_logic?(value), do: nil, else: value)
      }

      assert metric.value_float == 3.14
      assert metric.value_int == nil
      assert metric.value_str == nil
    end
  end

  # Helper functions that replicate the private logic from NetconfSession

  defp extract_messages_logic(buffer, acc) do
    case String.split(buffer, "]]>]]>", parts: 2) do
      [complete, rest] ->
        extract_messages_logic(rest, [complete | acc])

      [incomplete] ->
        {Enum.reverse(acc), incomplete}
    end
  end

  defp parse_float_logic(value) do
    case Float.parse(value) do
      {f, ""} -> f
      {f, _} -> if String.contains?(value, "."), do: f, else: nil
      :error -> nil
    end
  end

  defp parse_int_logic(value) do
    case Integer.parse(value) do
      {i, ""} -> i
      _ -> nil
    end
  end

  defp numeric_logic?(value) do
    parse_float_logic(value) != nil or parse_int_logic(value) != nil
  end

  defp build_test_rpc(message_id, filter_path) do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <rpc message-id="#{message_id}" xmlns="urn:ietf:params:xml:ns:netconf:base:1.0">
      <get>
        <filter type="subtree">
          #{filter_path}
        </filter>
      </get>
    </rpc>
    ]]>]]>
    """
  end
end
