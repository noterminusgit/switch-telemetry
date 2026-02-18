defmodule SwitchTelemetry.Collector.SubscriptionPaths do
  @moduledoc """
  Loads gNMI subscription path suggestions from reference JSON files.

  Paths are organized by platform with optional device-model-specific overrides.
  """

  @type path_entry :: %{path: String.t(), description: String.t(), category: String.t()}

  @doc """
  Lists available gNMI paths for the given platform, with optional device model overrides.

  Loads `_common.json` + platform-specific JSON. If `device_model` is given,
  overlays paths from `device_overrides/<model>.json`.
  """
  @spec list_paths(atom(), String.t() | nil) :: [path_entry()]
  def list_paths(platform, device_model \\ nil) do
    common_paths = load_paths_file("_common.json")
    platform_paths = load_paths_file("#{platform}.json")
    override_paths = load_device_override(device_model)

    (common_paths ++ platform_paths ++ override_paths)
    |> Enum.uniq_by(& &1.path)
  end

  @doc """
  Saves device-model-specific path overrides to `device_overrides/<model>.json`.
  """
  @spec save_device_override(String.t(), [path_entry()]) :: :ok | {:error, term()}
  def save_device_override(device_model, paths) when is_binary(device_model) do
    dir = Path.join(paths_dir(), "device_overrides")
    File.mkdir_p!(dir)

    data = %{
      "device_model" => device_model,
      "paths" =>
        Enum.map(paths, fn entry ->
          %{
            "path" => entry.path,
            "description" => Map.get(entry, :description, ""),
            "category" => Map.get(entry, :category, "device")
          }
        end)
    }

    file_path = Path.join(dir, "#{sanitize_filename(device_model)}.json")

    case Jason.encode(data, pretty: true) do
      {:ok, json} ->
        File.write!(file_path, json)
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  # --- Private ---

  defp load_paths_file(filename) do
    path = Path.join(paths_dir(), filename)

    case File.read(path) do
      {:ok, contents} ->
        case Jason.decode(contents) do
          {:ok, %{"paths" => paths}} ->
            Enum.map(paths, &normalize_path_entry/1)

          _ ->
            []
        end

      {:error, _} ->
        []
    end
  end

  defp load_device_override(nil), do: []

  defp load_device_override(device_model) do
    filename = "#{sanitize_filename(device_model)}.json"
    path = Path.join([paths_dir(), "device_overrides", filename])

    case File.read(path) do
      {:ok, contents} ->
        case Jason.decode(contents) do
          {:ok, %{"paths" => paths}} ->
            Enum.map(paths, &normalize_path_entry/1)

          _ ->
            []
        end

      {:error, _} ->
        []
    end
  end

  defp normalize_path_entry(%{"path" => path} = entry) do
    %{
      path: path,
      description: Map.get(entry, "description", ""),
      category: Map.get(entry, "category", "other")
    }
  end

  defp normalize_path_entry(_), do: nil

  defp paths_dir do
    Application.app_dir(:switch_telemetry, "priv/gnmi_paths")
  end

  defp sanitize_filename(name) do
    name
    |> String.replace(~r/[^a-zA-Z0-9_\-]/, "_")
    |> String.slice(0, 100)
  end
end
