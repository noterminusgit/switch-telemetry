defmodule SwitchTelemetryWeb.AlertLive.ChannelForm do
  use SwitchTelemetryWeb, :live_component

  alias SwitchTelemetry.Alerting

  @impl true
  def update(assigns, socket) do
    channel = assigns.channel
    config = channel.config || %{}

    {:ok,
     socket
     |> assign(assigns)
     |> assign(
       form_values: %{
         "name" => channel.name || "",
         "type" => (channel.type && to_string(channel.type)) || "webhook",
         "enabled" => if(channel.enabled != false, do: "true", else: "false"),
         "webhook_url" => config["url"] || "",
         "slack_url" => config["url"] || "",
         "email_to" => config["to"] || "",
         "email_from" => config["from"] || ""
       },
       selected_type: (channel.type && to_string(channel.type)) || "webhook"
     )}
  end

  @impl true
  def handle_event("type_changed", %{"channel" => %{"type" => type}}, socket) do
    {:noreply, assign(socket, selected_type: type)}
  end

  def handle_event("save_channel", %{"channel" => channel_params}, socket) do
    channel_params = parse_channel_params(channel_params, socket.assigns.channel.id)

    result =
      case socket.assigns.action do
        :new_channel ->
          Alerting.create_channel(channel_params)

        :edit_channel ->
          Alerting.update_channel(socket.assigns.channel, channel_params)
      end

    case result do
      {:ok, _channel} ->
        {:noreply,
         socket
         |> put_flash(:info, "Channel saved")
         |> push_navigate(to: ~p"/alerts/channels")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to save channel")}
    end
  end

  defp parse_channel_params(params, id) do
    type = params["type"]

    config =
      case type do
        "webhook" -> %{"url" => params["webhook_url"] || ""}
        "slack" -> %{"url" => params["slack_url"] || ""}
        "email" -> %{"to" => params["email_to"] || "", "from" => params["email_from"] || ""}
        _ -> %{}
      end

    %{
      "id" => id,
      "name" => params["name"],
      "type" => type,
      "enabled" => params["enabled"] == "true",
      "config" => config
    }
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.simple_form for={%{}} phx-submit="save_channel" phx-change="type_changed" phx-target={@myself}>
        <.input type="text" name="channel[name]" label="Name" value={@form_values["name"]} required />
        <.input
          type="select"
          name="channel[type]"
          label="Type"
          options={[
            {"Webhook", "webhook"},
            {"Slack", "slack"},
            {"Email", "email"}
          ]}
          value={@selected_type}
          required
        />
        <.input
          type="select"
          name="channel[enabled]"
          label="Enabled"
          options={[{"Yes", "true"}, {"No", "false"}]}
          value={@form_values["enabled"]}
        />

        <%= if @selected_type == "webhook" do %>
          <.input type="text" name="channel[webhook_url]" label="Webhook URL" value={@form_values["webhook_url"]} required />
        <% end %>

        <%= if @selected_type == "slack" do %>
          <.input type="text" name="channel[slack_url]" label="Slack Webhook URL" value={@form_values["slack_url"]} required />
        <% end %>

        <%= if @selected_type == "email" do %>
          <.input type="text" name="channel[email_to]" label="To (comma-separated)" value={@form_values["email_to"]} required />
          <.input type="text" name="channel[email_from]" label="From" value={@form_values["email_from"]} required />
        <% end %>

        <:actions>
          <.button type="submit">Save Channel</.button>
          <.link navigate={~p"/alerts/channels"} class="ml-4 text-gray-600">Cancel</.link>
        </:actions>
      </.simple_form>
    </div>
    """
  end
end
