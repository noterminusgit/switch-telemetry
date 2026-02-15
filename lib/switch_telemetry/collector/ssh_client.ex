defmodule SwitchTelemetry.Collector.SshClient do
  @moduledoc "Behaviour wrapping SSH client operations for NETCONF sessions."

  @callback connect(charlist(), integer(), keyword()) :: {:ok, pid()} | {:error, term()}
  @callback session_channel(pid(), integer()) :: {:ok, integer()} | {:error, term()}
  @callback subsystem(pid(), integer(), charlist(), integer()) :: :success | :failure
  @callback send(pid(), integer(), iodata()) :: :ok | {:error, term()}
  @callback close(pid()) :: :ok
end

defmodule SwitchTelemetry.Collector.DefaultSshClient do
  @moduledoc false
  @behaviour SwitchTelemetry.Collector.SshClient

  @impl true
  def connect(host, port, opts), do: :ssh.connect(host, port, opts)

  @impl true
  def session_channel(ssh_ref, timeout), do: :ssh_connection.session_channel(ssh_ref, timeout)

  @impl true
  def subsystem(ssh_ref, channel_id, subsystem, timeout),
    do: :ssh_connection.subsystem(ssh_ref, channel_id, subsystem, timeout)

  @impl true
  def send(ssh_ref, channel_id, data), do: :ssh_connection.send(ssh_ref, channel_id, data)

  @impl true
  def close(ssh_ref), do: :ssh.close(ssh_ref)
end
