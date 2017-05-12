defmodule BotApp do
  use Application

  def start(_type, _args) do
    import Supervisor.Spec

    slack_token = System.get_env("SLACK_TOKEN")

    # Define workers and child supervisors to be supervised
    children = [
      worker(Slack.Bot, [Bot, [], slack_token]),
      supervisor(Registry, [:unique, :games_registry])
    ]

    # See http://elixir-lang.org/docs/stable/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Eslixir.Supervisor]
    Supervisor.start_link(children, opts)
  end
end

defmodule Bot do
  use Slack

  def handle_connect(slack, state) do
    IO.puts "Connected as #{slack.me.name}"
    {:ok, state}
  end

  def handle_event(message = %{type: "message"}, slack, state) do
    with {_, {_, pid}} <- Game.start_link(message.user) do
      pid |> Game.next_message(message)
      |> send_message(message.channel, slack)
    end
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

defmodule Enemy, do: defstruct [:name, :damage, :health]

defmodule Player do
  defstruct [:room, :items, :health]

  def has_item?(player, item_name), do: player.items |> Enum.member?(item_name)
end

defmodule Room do
  defstruct [:text, :doors, :name, :items, :enemy]

  def door(room, door_name), do: room.doors |> Enum.find(fn(door) -> door.name == door_name end)
  def has_item?(room, item_name), do: room.items |> Enum.find(fn(item) -> item == item_name end)
end

defmodule Door do
  defstruct [:name, :room, :needs_key]

  def can_enter?(door, player), do: !door.needs_key || player |> Player.has_item?(door.needs_key)
end

defmodule Item do
  defstruct [:name, :text, :damage]
end

defmodule Items do
  @items [
    %Item{name: "keyfob", text: "A keyfob. Maybe it opens something?", damage: 1},
    %Item{name: "coffee", text: "Hot Coffee, handle with care", damage: 1},
    %Item{name: "stapler", text: "A normal plastic stapler", damage: 35}
  ]

  def find(item_name), do: @items |> Enum.find(fn(item) -> item.name == item_name end)
end

defmodule Enemies do
  @enemies [
    %Enemy{
      name: "Ruben",
      damage: 20,
      health: 100
    },
    %Enemy{
      name: "Jaap",
      damage: 30,
      health: 100
    }
  ]

  def enemies, do: @enemies

  def enemy(name) do
    @enemies |> Enum.find(fn(enemy) -> enemy.name == name end)
  end
end

defmodule Rooms do
  @rooms [
    %Room{
      name: "the parking lot",
      text: "You are on the parking lot of YoungCapital, the flags are moving in the wind. Looking at the building you see that there are two entrances, an `orange door` on the left with a big YoungCapital sign above it, and a `glass door` on right. Which door do you pick?",
      doors: [
        %Door{name: "glass door", room: "glass lobby", needs_key: "keyfob"},
        %Door{name: "orange door", room: "main lobby"}
        ],
      items: ["keyfob"],
    },
    %Room{
      name: "main lobby",
      text: "You are now in the main lobby. You are greeted by the smell of fresh coffee and see the reception desk with a friendly receptionist in front of it. There is a coffee machine to the right. What do you do? `pick up coffee`, go through `green door` or `talk to receptionist`",
      doors: [%Door{name: "green door", room: "conference room"}],
      items: ["coffee", "stapler"],
    },
    %Room{
      name: "glass lobby",
      text: "You are now in the glass lobby. Oh no!, You see enemy *Jaap*. Do you want to `fight` or `run`?",
      doors: [%Door{name: "X", room: "the parking lot"}],
      items: [],
      enemy: "Jaap"
    },
    %Room{
      name: "conference room",
      text: "You are in the conference room. Oh oh! Your mortal enemy *Ruben* is here! What do you want to do? `fight` or `run`",
      doors: [],
      items: [],
      enemy: "Ruben"
    },
  ]

  def rooms, do: @rooms

  def room(name) do
    @rooms |> Enum.find(fn(room) -> room.name == name end)
  end
end

defmodule Game do
  use GenServer

  defstruct [:player, :enemy]

  def start_link(user_id) do
    name = via_tuple(user_id)
    GenServer.start_link(__MODULE__, %Game{player: %Player{room: "the parking lot", items: [], health: 100}}, name: name)
  end

  defp via_tuple(user_id) do
    {:via, Registry, {:games_registry, user_id}}
  end

  def next_message(pid, message) do
    GenServer.call(pid, {:next_message, message})
  end

  def current_room(state), do: Rooms.room(state.player.room)
  def owned_items(state), do: state.player.items

  def process_message("h", state), do: process_message("help", state)
  def process_message("help", state) do
    {"Possible command are: `open <door>`, `where am i`, `look around`, `pick up <item>`, `attack with <item>`, `run`", state}
  end

  def process_message("fight", %{enemy: %Enemy{}} = state) do
    items = owned_items(state)
    case length(items) do
      0 -> {"You don't have any items to attack", state}
      _ -> {"What do you want to attack with (attack with `item_name`):  #{items |> Enum.map(fn(item) -> "#{item}" end) |> Enum.join("\n")}", state}
    end
  end

  def process_message("attack with " <> item_name, %{enemy: %Enemy{}} = state) do
    item = Items.find(item_name)
    enemy = state.enemy
    new_health = enemy.health - item.damage

    if new_health > 0 do
      {"You have done #{item.damage} damage, but #{enemy.name} is still not defeated", %Game{state | enemy: %Enemy{enemy | health: new_health}}}
    else
      {"You have defeated #{enemy.name}", %Game{state | enemy: nil}}
    end
  end

  def process_message("run", %{enemy: %Enemy{}} = state) do
    goto_room(Rooms.room("the parking lot"), %Game{state | enemy: nil})
  end

  def process_message("look around", state) do
    items = current_room(state).items |> Enum.map(&Items.find/1)
    case length(items) do
      0 -> {"You don't see anything", state}
      1 -> {"You see something: #{items |> Enum.map(fn(item) -> "#{item.text}" end) |> Enum.join("\n")}", state}
      _ -> {"You see a few things lying around:\n#{items |> Enum.map(fn(item) -> "  #{item.text}" end) |> Enum.join("\n")}", state}
    end
  end

  def process_message("where am i", %{enemy: %Enemy{}} = state) do
    {"You're in front of your mortal enemy #{state.enemy.name}", state}
  end
  def process_message("where am i", state) do
    {current_room(state).text, state}
  end

  def process_message("open " <> door, state) do
    door = current_room(state) |> Room.door(door)
    if(door) do
      if(door |> Door.can_enter?(state.player)) do
        goto_room(Rooms.room(door.room), state)
      else
        {"This door needs #{door.needs_key} to open!", state}
      end
    else
      {"You can't get to there from here", state}
    end
  end

  def process_message("pick up " <> item_name, state) do
    room = current_room(state)
    item = Items.find(item_name)
    if(room |> Room.has_item?(item_name)) do
      {"You picked up #{item.name}. #{item.text}", %Game{state | player: %Player{state.player | items: state.player.items ++ [item.name]}}}
    else
      {"What? Are you going crazy?", state}
    end
  end

  def process_message(message, state) do
    {Rooms.room(state.player.room).text, state}
  end

  def goto_room(nil, _), do: {"Unknown room", %{}}
  def goto_room(%Room{enemy: nil} = next_room, state) do
    {next_room.text, %Game{state | player: %Player{state.player | room: next_room.name}}}
  end
  def goto_room(%Room{enemy: enemy_name} = next_room, state) do
    enemy = Enemies.enemy(enemy_name)
    {"You see #{enemy.name} in the room. It blocks you form entering the room. What do you do `run` or `fight`", %Game{state | player: %Player{state.player | room: next_room.name}, enemy: enemy}}
  end

  def handle_call({:next_message, message}, _from, state) do
    IO.inspect message
    IO.inspect state
    {message, new_state} = process_message(message.text, state) |> IO.inspect

    {:reply, message, new_state}
  end
end
