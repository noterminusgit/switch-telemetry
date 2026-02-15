defmodule SwitchTelemetry.Collector.SubscriptionPropertyTest do
  use SwitchTelemetry.DataCase, async: true
  use ExUnitProperties

  alias SwitchTelemetry.Collector.Subscription

  @base_attrs %{id: "sub_prop_test", device_id: "dev_prop_test"}

  # ---------------------------------------------------------------
  # Generators
  # ---------------------------------------------------------------

  # Generate a valid path segment (alphanumeric plus underscore, dash, dot, colon)
  defp valid_path_char_gen do
    member_of(
      Enum.concat([
        Enum.to_list(?a..?z),
        Enum.to_list(?A..?Z),
        Enum.to_list(?0..?9),
        [?_, ?-, ?., ?:, ?/]
      ])
    )
  end

  defp valid_path_gen do
    gen all(chars <- list_of(valid_path_char_gen(), min_length: 1, max_length: 50)) do
      "/" <> List.to_string(chars)
    end
  end

  # ---------------------------------------------------------------
  # Paths with injection characters always produce errors
  # ---------------------------------------------------------------
  describe "path validation — injection characters" do
    property "paths containing < always produce changeset errors" do
      check all(
              prefix <- string(:alphanumeric, min_length: 1, max_length: 10),
              suffix <- string(:alphanumeric, min_length: 0, max_length: 10)
            ) do
        path = "/#{prefix}<#{suffix}"
        attrs = Map.put(@base_attrs, :paths, [path])
        changeset = Subscription.changeset(%Subscription{}, attrs)
        refute changeset.valid?
        assert %{paths: [msg]} = errors_on(changeset)
        assert msg =~ "invalid"
      end
    end

    property "paths containing > always produce changeset errors" do
      check all(
              prefix <- string(:alphanumeric, min_length: 1, max_length: 10),
              suffix <- string(:alphanumeric, min_length: 0, max_length: 10)
            ) do
        path = "/#{prefix}>#{suffix}"
        attrs = Map.put(@base_attrs, :paths, [path])
        changeset = Subscription.changeset(%Subscription{}, attrs)
        refute changeset.valid?
        assert %{paths: [msg]} = errors_on(changeset)
        assert msg =~ "invalid"
      end
    end

    property "paths containing & always produce changeset errors" do
      check all(
              prefix <- string(:alphanumeric, min_length: 1, max_length: 10),
              suffix <- string(:alphanumeric, min_length: 0, max_length: 10)
            ) do
        path = "/#{prefix}&#{suffix}"
        attrs = Map.put(@base_attrs, :paths, [path])
        changeset = Subscription.changeset(%Subscription{}, attrs)
        refute changeset.valid?
        assert %{paths: [msg]} = errors_on(changeset)
        assert msg =~ "invalid"
      end
    end

    property "paths containing ; always produce changeset errors" do
      check all(
              prefix <- string(:alphanumeric, min_length: 1, max_length: 10),
              suffix <- string(:alphanumeric, min_length: 0, max_length: 10)
            ) do
        path = "/#{prefix};#{suffix}"
        attrs = Map.put(@base_attrs, :paths, [path])
        changeset = Subscription.changeset(%Subscription{}, attrs)
        refute changeset.valid?
        assert %{paths: [msg]} = errors_on(changeset)
        assert msg =~ "invalid"
      end
    end

    property "paths containing -- always produce changeset errors" do
      check all(
              prefix <- string(:alphanumeric, min_length: 1, max_length: 10),
              suffix <- string(:alphanumeric, min_length: 0, max_length: 10)
            ) do
        path = "/#{prefix}--#{suffix}"
        attrs = Map.put(@base_attrs, :paths, [path])
        changeset = Subscription.changeset(%Subscription{}, attrs)
        refute changeset.valid?
        assert %{paths: [msg]} = errors_on(changeset)
        assert msg =~ "invalid"
      end
    end
  end

  # ---------------------------------------------------------------
  # Paths > 512 chars always produce errors
  # ---------------------------------------------------------------
  describe "path validation — length" do
    property "paths longer than 512 characters always produce errors" do
      check all(extra_len <- integer(1..200)) do
        # Build a valid-looking path that exceeds 512 chars
        path = "/" <> String.duplicate("a", 512 + extra_len)

        attrs = Map.put(@base_attrs, :paths, [path])
        changeset = Subscription.changeset(%Subscription{}, attrs)
        refute changeset.valid?
        errors = errors_on(changeset)
        assert Map.has_key?(errors, :paths)
      end
    end
  end

  # ---------------------------------------------------------------
  # Valid paths matching the regex pass validation
  # ---------------------------------------------------------------
  describe "path validation — valid paths" do
    property "paths matching ^/[a-zA-Z0-9/_\\-\\.:]+$ pass validation" do
      check all(path <- valid_path_gen()) do
        # Ensure the generated path actually matches the validation regex
        # and does not contain injection chars or --
        if String.match?(path, ~r{^/[a-zA-Z0-9/_\-\.:]+$}) and
             not String.contains?(path, "--") and
             String.length(path) <= 512 do
          attrs = Map.put(@base_attrs, :paths, [path])
          changeset = Subscription.changeset(%Subscription{}, attrs)

          # The changeset should not have path-related errors
          errors = errors_on(changeset)
          refute Map.has_key?(errors, :paths), "Expected path #{inspect(path)} to be valid"
        end
      end
    end
  end
end
