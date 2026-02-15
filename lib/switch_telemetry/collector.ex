defmodule SwitchTelemetry.Collector do
  @moduledoc """
  Context for managing telemetry collection subscriptions.
  """
  import Ecto.Query

  alias SwitchTelemetry.Repo
  alias SwitchTelemetry.Collector.Subscription

  # --- Subscriptions ---

  @spec list_subscriptions() :: [Subscription.t()]
  def list_subscriptions do
    Repo.all(from s in Subscription, preload: [:device])
  end

  @spec list_subscriptions_for_device(String.t()) :: [Subscription.t()]
  def list_subscriptions_for_device(device_id) do
    from(s in Subscription,
      where: s.device_id == ^device_id,
      order_by: [asc: :inserted_at]
    )
    |> Repo.all()
  end

  @spec get_subscription!(String.t()) :: Subscription.t()
  def get_subscription!(id), do: Repo.get!(Subscription, id) |> Repo.preload(:device)

  @spec get_subscription(String.t()) :: Subscription.t() | nil
  def get_subscription(id), do: Repo.get(Subscription, id)

  @spec create_subscription(map()) :: {:ok, Subscription.t()} | {:error, Ecto.Changeset.t()}
  def create_subscription(attrs) do
    %Subscription{}
    |> Subscription.changeset(attrs)
    |> Repo.insert()
  end

  @spec update_subscription(Subscription.t(), map()) ::
          {:ok, Subscription.t()} | {:error, Ecto.Changeset.t()}
  def update_subscription(%Subscription{} = subscription, attrs) do
    subscription
    |> Subscription.changeset(attrs)
    |> Repo.update()
  end

  @spec delete_subscription(Subscription.t()) ::
          {:ok, Subscription.t()} | {:error, Ecto.Changeset.t()}
  def delete_subscription(%Subscription{} = subscription) do
    Repo.delete(subscription)
  end

  @spec change_subscription(Subscription.t(), map()) :: Ecto.Changeset.t()
  def change_subscription(%Subscription{} = subscription, attrs \\ %{}) do
    Subscription.changeset(subscription, attrs)
  end

  @spec toggle_subscription(Subscription.t()) ::
          {:ok, Subscription.t()} | {:error, Ecto.Changeset.t()}
  def toggle_subscription(%Subscription{} = subscription) do
    update_subscription(subscription, %{enabled: !subscription.enabled})
  end
end
