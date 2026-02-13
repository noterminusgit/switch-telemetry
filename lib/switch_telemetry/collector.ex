defmodule SwitchTelemetry.Collector do
  @moduledoc """
  Context for managing telemetry collection subscriptions.
  """
  import Ecto.Query

  alias SwitchTelemetry.Repo
  alias SwitchTelemetry.Collector.Subscription

  # --- Subscriptions ---

  def list_subscriptions do
    Repo.all(from s in Subscription, preload: [:device])
  end

  def list_subscriptions_for_device(device_id) do
    from(s in Subscription,
      where: s.device_id == ^device_id,
      order_by: [asc: :inserted_at]
    )
    |> Repo.all()
  end

  def get_subscription!(id), do: Repo.get!(Subscription, id) |> Repo.preload(:device)

  def get_subscription(id), do: Repo.get(Subscription, id)

  def create_subscription(attrs) do
    %Subscription{}
    |> Subscription.changeset(attrs)
    |> Repo.insert()
  end

  def update_subscription(%Subscription{} = subscription, attrs) do
    subscription
    |> Subscription.changeset(attrs)
    |> Repo.update()
  end

  def delete_subscription(%Subscription{} = subscription) do
    Repo.delete(subscription)
  end

  def change_subscription(%Subscription{} = subscription, attrs \\ %{}) do
    Subscription.changeset(subscription, attrs)
  end

  def toggle_subscription(%Subscription{} = subscription) do
    update_subscription(subscription, %{enabled: !subscription.enabled})
  end
end
