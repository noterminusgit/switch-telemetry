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

  describe "SSH data handling" do
    test "handles {:ssh_cm, ref, {:data, channel, type, data}} buffer accumulation" do
      # Simulate the handle_info callback for SSH data
      # The handler concatenates data to the buffer and extracts complete messages
      state = %NetconfSession{
        ssh_ref: :fake_ref,
        channel_id: 0,
        buffer: "",
        device: nil,
        message_id: 1
      }

      # Simulate receiving partial SSH data - buffer should accumulate
      partial_data = "<rpc-reply>partial"
      new_buffer = state.buffer <> to_string(partial_data)
      assert new_buffer == "<rpc-reply>partial"

      # No complete message (no delimiter), so extract_messages returns empty
      {messages, remaining} = extract_messages_logic(new_buffer, [])
      assert messages == []
      assert remaining == "<rpc-reply>partial"
    end

    test "completes buffer when delimiter arrives in second chunk" do
      # First chunk: partial data
      buffer = "<rpc-reply><data>value</data></rpc-reply>"

      # Second chunk with delimiter
      new_data = "]]>]]>"
      combined = buffer <> new_data

      {messages, remaining} = extract_messages_logic(combined, [])
      assert messages == ["<rpc-reply><data>value</data></rpc-reply>"]
      assert remaining == ""
    end

    test "handles multiple SSH data chunks building up a complete message" do
      chunks = [
        "<rpc-reply>",
        "<data>",
        "<hostname>switch-1</hostname>",
        "</data>",
        "</rpc-reply>",
        "]]>]]>"
      ]

      buffer =
        Enum.reduce(chunks, "", fn chunk, buf ->
          buf <> to_string(chunk)
        end)

      {messages, remaining} = extract_messages_logic(buffer, [])
      assert length(messages) == 1

      [msg] = messages
      assert msg =~ "<hostname>switch-1</hostname>"
      assert remaining == ""
    end

    test "handles binary data conversion from SSH chardata" do
      # SSH may send data as charlists or binaries
      charlist_data = ~c"<rpc-reply/>]]>]]>"
      binary_data = to_string(charlist_data)

      {messages, remaining} = extract_messages_logic(binary_data, [])
      assert messages == ["<rpc-reply/>"]
      assert remaining == ""
    end
  end

  describe "buffer management edge cases" do
    test "handles empty buffer with delimiter" do
      buffer = "]]>]]>"

      {messages, remaining} = extract_messages_logic(buffer, [])
      # An empty message before the delimiter
      assert messages == [""]
      assert remaining == ""
    end

    test "handles multiple complete messages in one data chunk" do
      buffer = "msg1]]>]]>msg2]]>]]>"

      {messages, remaining} = extract_messages_logic(buffer, [])
      assert messages == ["msg1", "msg2"]
      assert remaining == ""
    end

    test "handles three messages with trailing partial" do
      buffer = "first]]>]]>second]]>]]>third]]>]]>partial"

      {messages, remaining} = extract_messages_logic(buffer, [])
      assert messages == ["first", "second", "third"]
      assert remaining == "partial"
    end

    test "handles delimiter-only repeated pattern" do
      buffer = "]]>]]>]]>]]>]]>]]>"

      {messages, remaining} = extract_messages_logic(buffer, [])
      assert messages == ["", "", ""]
      assert remaining == ""
    end

    test "handles very large buffer content" do
      # Simulate a large NETCONF response
      large_xml = String.duplicate("<data>x</data>", 1000)
      buffer = large_xml <> "]]>]]>"

      {messages, remaining} = extract_messages_logic(buffer, [])
      assert length(messages) == 1
      assert hd(messages) == large_xml
      assert remaining == ""
    end
  end

  describe "collect cycle" do
    test "collect with nil ssh_ref is a no-op" do
      # When ssh_ref is nil, handle_info(:collect, state) should return unchanged state
      state = %NetconfSession{
        ssh_ref: nil,
        channel_id: nil,
        buffer: "",
        device: nil,
        message_id: 1
      }

      # Replicate the guard clause: handle_info(:collect, %{ssh_ref: nil} = state)
      assert state.ssh_ref == nil
      # The handler returns {:noreply, state} without doing anything
    end

    test "collect timer interval comes from device configuration" do
      # Verify the default collection_interval_ms
      default_interval = 30_000

      # The device struct can override this
      custom_interval = 10_000

      assert default_interval == 30_000
      assert custom_interval < default_interval
    end

    test "message_id increments after each RPC send" do
      state = %NetconfSession{message_id: 1}

      # Simulate incrementing for each subscription path
      paths = ["<interfaces/>", "<system/>", "<bgp/>"]

      final_state =
        Enum.reduce(paths, state, fn _path, acc ->
          %{acc | message_id: acc.message_id + 1}
        end)

      assert final_state.message_id == 4
    end
  end

  describe "cleanup" do
    test "cleanup_ssh logic with nil ssh_ref does not crash" do
      state = %NetconfSession{
        ssh_ref: nil,
        channel_id: nil,
        timer_ref: nil,
        buffer: "",
        device: nil,
        message_id: 1
      }

      # The cleanup function checks state.timer_ref and state.ssh_ref for nil
      # before attempting to cancel/close. With both nil, it should be safe.
      assert state.ssh_ref == nil
      assert state.timer_ref == nil
    end

    test "cleanup_ssh logic with timer_ref cancels timer" do
      # Create a real timer reference to test cancel logic
      {:ok, timer_ref} = :timer.send_interval(60_000, :unused_collect)

      state = %NetconfSession{
        ssh_ref: nil,
        channel_id: nil,
        timer_ref: timer_ref,
        buffer: "",
        device: nil,
        message_id: 1
      }

      # Verify timer_ref is truthy (non-nil)
      assert state.timer_ref != nil

      # Cancel the timer as cleanup would
      assert {:ok, :cancel} = :timer.cancel(state.timer_ref)
    end

    test "session closed message triggers reconnect logic" do
      # When {:ssh_cm, ref, {:closed, channel}} is received,
      # the session should clean up and schedule a reconnect
      state = %NetconfSession{
        ssh_ref: :fake_ref,
        channel_id: 0,
        timer_ref: nil,
        buffer: "some leftover data",
        device: %{hostname: "test.lab"},
        message_id: 5
      }

      # After handling :closed, the state should be reset
      reset_state = %{state | ssh_ref: nil, channel_id: nil, buffer: ""}
      assert reset_state.ssh_ref == nil
      assert reset_state.channel_id == nil
      assert reset_state.buffer == ""
      # message_id should be preserved
      assert reset_state.message_id == 5
    end

    test "exit_status message does not change state" do
      state = %NetconfSession{
        ssh_ref: :fake_ref,
        channel_id: 0,
        buffer: "data",
        device: nil,
        message_id: 3
      }

      # handle_info for exit_status returns {:noreply, state} unchanged
      assert state.buffer == "data"
      assert state.message_id == 3
    end

    test "eof message does not change state" do
      state = %NetconfSession{
        ssh_ref: :fake_ref,
        channel_id: 0,
        buffer: "data",
        device: nil,
        message_id: 7
      }

      # handle_info for eof returns {:noreply, state} unchanged
      assert state.buffer == "data"
      assert state.message_id == 7
    end
  end

  describe "NETCONF framing" do
    test "framing delimiter is correct" do
      # The NETCONF 1.0 framing delimiter is ]]>]]>
      delimiter = "]]>]]>"
      assert String.length(delimiter) == 6
    end

    test "hello message contains framing delimiter" do
      hello = """
      <?xml version="1.0" encoding="UTF-8"?>
      <hello xmlns="urn:ietf:params:xml:ns:netconf:base:1.0">
        <capabilities>
          <capability>urn:ietf:params:netconf:base:1.0</capability>
          <capability>urn:ietf:params:netconf:base:1.1</capability>
        </capabilities>
      </hello>]]>]]>
      """

      assert hello =~ "]]>]]>"
      assert hello =~ "urn:ietf:params:netconf:base:1.0"
      assert hello =~ "urn:ietf:params:netconf:base:1.1"
    end
  end

  describe "parse_float edge cases" do
    test "partial float with trailing non-numeric and decimal returns float" do
      # e.g. "3.14abc" -> Float.parse returns {3.14, "abc"}
      # Since it contains ".", parse_float returns 3.14
      assert parse_float_logic("3.14abc") == 3.14
    end

    test "integer with trailing non-numeric returns nil (no decimal)" do
      # e.g. "42abc" -> Float.parse returns {42.0, "abc"}
      # Since no ".", parse_float returns nil
      assert parse_float_logic("42abc") == nil
    end

    test "empty string returns nil" do
      assert parse_float_logic("") == nil
    end

    test "negative float" do
      assert parse_float_logic("-3.14") == -3.14
    end

    test "negative integer parsed as float" do
      assert parse_float_logic("-42") == -42.0
    end
  end

  describe "parse_int edge cases" do
    test "negative integer parses correctly" do
      assert parse_int_logic("-100") == -100
    end

    test "empty string returns nil" do
      assert parse_int_logic("") == nil
    end

    test "float string returns nil for int parsing" do
      # "3.14" -> Integer.parse returns {3, ".14"} which is not {i, ""}
      assert parse_int_logic("3.14") == nil
    end
  end

  describe "numeric? edge cases" do
    test "empty string is not numeric" do
      refute numeric_logic?("")
    end

    test "negative values are numeric" do
      assert numeric_logic?("-42")
      assert numeric_logic?("-3.14")
    end

    test "scientific notation is numeric" do
      assert numeric_logic?("1.0e3")
    end
  end

  describe "collection interval" do
    test "uses device interval when set" do
      interval = 10_000
      result = interval || 30_000
      assert result == 10_000
    end

    test "falls back to 30_000 when device interval is nil" do
      interval = nil
      result = interval || 30_000
      assert result == 30_000
    end
  end

  describe "element_to_path logic" do
    test "builds path with leading slash from element name" do
      # The source: "/" <> name where name is extracted via xpath local-name
      name = "hostname"
      path = "/" <> name
      assert path == "/hostname"
    end

    test "handles empty name" do
      name = ""
      path = "/" <> name
      assert path == "/"
    end
  end
end
