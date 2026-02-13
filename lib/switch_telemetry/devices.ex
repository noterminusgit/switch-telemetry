defmodule SwitchTelemetry.Devices do
  @moduledoc """
  Context for managing network devices and credentials.
  """
  import Ecto.Query

  alias SwitchTelemetry.Repo
  alias SwitchTelemetry.Devices.{Credential, Device}

  # --- Devices ---

  def list_devices do
    Repo.all(Device)
  end

  def list_devices_by_status(status) do
    from(d in Device, where: d.status == ^status)
    |> Repo.all()
  end

  def get_device!(id), do: Repo.get!(Device, id)

  def get_device(id), do: Repo.get(Device, id)

  def create_device(attrs) do
    %Device{}
    |> Device.changeset(attrs)
    |> Repo.insert()
  end

  def update_device(%Device{} = device, attrs) do
    device
    |> Device.changeset(attrs)
    |> Repo.update()
  end

  def delete_device(%Device{} = device) do
    Repo.delete(device)
  end

  def list_devices_for_collector(collector_node) do
    from(d in Device,
      where: d.assigned_collector == ^collector_node and d.status == :active
    )
    |> Repo.all()
  end

  def change_device(%Device{} = device, attrs \\ %{}) do
    Device.changeset(device, attrs)
  end

  def get_device_with_credential!(id) do
    Device
    |> Repo.get!(id)
    |> Repo.preload(:credential)
  end

  def get_device_with_subscriptions!(id) do
    Device
    |> Repo.get!(id)
    |> Repo.preload(:subscriptions)
  end

  # --- Credentials ---

  def list_credentials do
    Repo.all(Credential)
  end

  def get_credential!(id), do: Repo.get!(Credential, id)

  def get_credential(id), do: Repo.get(Credential, id)

  def create_credential(attrs) do
    %Credential{}
    |> Credential.changeset(attrs)
    |> Repo.insert()
  end

  def update_credential(%Credential{} = credential, attrs) do
    credential
    |> Credential.changeset(attrs)
    |> Repo.update()
  end

  def delete_credential(%Credential{} = credential) do
    Repo.delete(credential)
  end

  def change_credential(%Credential{} = credential, attrs \\ %{}) do
    Credential.changeset(credential, attrs)
  end

  def list_credentials_for_select do
    from(c in Credential, select: {c.name, c.id}, order_by: c.name)
    |> Repo.all()
  end
end
