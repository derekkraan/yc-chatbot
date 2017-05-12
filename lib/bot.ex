defmodule BotApp do
  use Application

  def start(_type, _args) do
    Slack.Bot.start_link(Bot, [], "xoxb-182545675987-XOPAeC0fLCBRkZxNpnM7J7Ez")
  end
end

defmodule Bot do
  use Slack

  def handle_connect(slack, state) do
    IO.puts "Connected as #{slack.me.name}"
    {:ok, state}
  end

  def handle_event(message = %{type: "message"}, slack, state) do
    IO.puts "GOT MESSAGE"
    send_message("I got a message!", message.channel, slack)
    {:ok, state}
  end

  def handle_event(_, _, state), do: {:ok, state}

  def handle_info({:message, text, channel}, slack, state) do
    IO.puts "Sending your message, captain!"

    send_message(text, channel, slack)

    {:ok, state}
  end

  def handle_info(_, _, state), do: {:ok, state}
end
