defmodule SwitchTelemetry.Devices do
  @moduledoc """
  Context for managing network devices and credentials.
  """
  import Ecto.Query

  alias SwitchTelemetry.Repo
  alias SwitchTelemetry.Devices.{Credential, Device}

  # --- Devices ---

  @spec list_devices() :: [Device.t()]
  def list_devices do
    Repo.all(Device)
  end

  @spec list_devices_by_status(atom()) :: [Device.t()]
  def list_devices_by_status(status) do
    from(d in Device, where: d.status == ^status)
    |> Repo.all()
  end

  @spec get_device!(String.t()) :: Device.t()
  def get_device!(id), do: Repo.get!(Device, id)

  @spec get_device(String.t()) :: Device.t() | nil
  def get_device(id), do: Repo.get(Device, id)

  @spec create_device(map()) :: {:ok, Device.t()} | {:error, Ecto.Changeset.t()}
  def create_device(attrs) do
    %Device{}
    |> Device.changeset(attrs)
    |> Repo.insert()
  end

  @spec update_device(Device.t(), map()) :: {:ok, Device.t()} | {:error, Ecto.Changeset.t()}
  def update_device(%Device{} = device, attrs) do
    device
    |> Device.changeset(attrs)
    |> Repo.update()
  end

  @spec delete_device(Device.t()) :: {:ok, Device.t()} | {:error, Ecto.Changeset.t()}
  def delete_device(%Device{} = device) do
    Repo.delete(device)
  end

  @spec update_device_model(Device.t(), String.t()) ::
          {:ok, Device.t()} | {:error, Ecto.Changeset.t()}
  def update_device_model(%Device{} = device, model) do
    update_device(device, %{model: model})
  end

  @spec list_devices_for_collector(String.t()) :: [Device.t()]
  def list_devices_for_collector(collector_node) do
    from(d in Device,
      where: d.assigned_collector == ^collector_node and d.status == :active
    )
    |> Repo.all()
  end

  @spec change_device(Device.t(), map()) :: Ecto.Changeset.t()
  def change_device(%Device{} = device, attrs \\ %{}) do
    Device.changeset(device, attrs)
  end

  @spec get_device_with_credential!(String.t()) :: Device.t()
  def get_device_with_credential!(id) do
    Device
    |> Repo.get!(id)
    |> Repo.preload(:credential)
  end

  @spec get_device_with_subscriptions!(String.t()) :: Device.t()
  def get_device_with_subscriptions!(id) do
    Device
    |> Repo.get!(id)
    |> Repo.preload(:subscriptions)
  end

  @doc """
  Returns the default gNMI encoding for a given platform.
  """
  @spec default_gnmi_encoding(atom() | String.t()) :: :proto | :json_ietf
  def default_gnmi_encoding(platform) when is_atom(platform),
    do: default_gnmi_encoding(to_string(platform))

  def default_gnmi_encoding("cisco_iosxr"), do: :proto
  def default_gnmi_encoding("cisco_iosxe"), do: :json_ietf
  def default_gnmi_encoding("cisco_nxos"), do: :json_ietf
  def default_gnmi_encoding("juniper_junos"), do: :proto
  def default_gnmi_encoding("arista_eos"), do: :json_ietf
  def default_gnmi_encoding("nokia_sros"), do: :json_ietf
  def default_gnmi_encoding(_), do: :proto

  # --- Credentials ---

  @spec list_credentials() :: [Credential.t()]
  def list_credentials do
    Repo.all(Credential)
  end

  @spec get_credential!(String.t()) :: Credential.t()
  def get_credential!(id), do: Repo.get!(Credential, id)

  @spec get_credential(String.t()) :: Credential.t() | nil
  def get_credential(id), do: Repo.get(Credential, id)

  @spec create_credential(map()) :: {:ok, Credential.t()} | {:error, Ecto.Changeset.t()}
  def create_credential(attrs) do
    %Credential{}
    |> Credential.changeset(attrs)
    |> Repo.insert()
  end

  @spec update_credential(Credential.t(), map()) ::
          {:ok, Credential.t()} | {:error, Ecto.Changeset.t()}
  def update_credential(%Credential{} = credential, attrs) do
    credential
    |> Credential.changeset(attrs)
    |> Repo.update()
  end

  @spec delete_credential(Credential.t()) :: {:ok, Credential.t()} | {:error, Ecto.Changeset.t()}
  def delete_credential(%Credential{} = credential) do
    Repo.delete(credential)
  end

  @spec change_credential(Credential.t(), map()) :: Ecto.Changeset.t()
  def change_credential(%Credential{} = credential, attrs \\ %{}) do
    Credential.changeset(credential, attrs)
  end

  @spec list_credentials_for_select() :: [{String.t(), String.t()}]
  def list_credentials_for_select do
    from(c in Credential, select: {c.name, c.id}, order_by: c.name)
    |> Repo.all()
  end
end
