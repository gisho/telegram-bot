http = require("socket.http")
https = require("ssl.https")
URL = require("socket.url")
json = (loadfile "./libs/JSON.lua")()
serpent = (loadfile "./libs/serpent.lua")()
zmq = require "lzmq"
require "./libs/zhelpers"
require("./bot/utils")

VERSION = '0.8.5'

-- bind to zmq
context = zmq.context()
reqclient = context:socket{zmq.REQ, connect = "tcp://localhost:5690"}
zassert(reqclient, err)
--publisher, err = context:socket{zmq.PUB, bind = "tcp://*:5563"}
--publisher, err = context:socket{zmq.PUB, bind = "tcp://*:5563"}
--zassert(publisher, err)
sleep (1);
--local subscriber, err = context:socket{zmq.SUB,
--  subscribe = "";
--  connect   = "tcp://localhost:5561";
--}

--zassert(subscriber, err)
-- 0MQ is so fast, we need to wait a while
--sleep (1);
can_start_sub=false
function on_msg_receive (msg)
  --vardump(msg)
  print(msg.text)
  if msg_valid(msg) == false then
    return
  end

  do_action(msg)
end

function ok_cb(extra, success, result)
end

function on_binlog_replay_end ()
  started = 1
  -- Uncomment the line to enable cron plugins.
  postpone (cron_plugins, false, 60*5.0)
  -- See plugins/ping.lua as an example for cron

  _config = load_config()

  -- load plugins
  plugins = {}
  load_plugins()
  print("start coroutine....")
  if can_start_sub == true then
      coroutine.resume(co)
  end
  --postpone (get_sub, false,5)
end

function msg_valid(msg)
  -- Dont process outgoing messages
  if msg.out then
    return false
  end
  if msg.date < now then
    return false
  end
  if msg.unread == 0 then
    return false
  end
end

function do_lex(msg, text)
  for name, desc in pairs(plugins) do
    if (desc.lex ~= nil) then
      result = desc.lex(msg, text)
      if (result ~= nil) then
        print ("Mutating to " .. result)
        text = result
      end
    end
  end
  return text
end

function do_action(msg)
  local receiver = get_receiver(msg)
  local text = msg.text
  print("received text >> ", msg.text)
  if msg.text == nil then
     return ''
  end
  mark_read(get_receiver(msg), ok_cb, false)

  --publisher:sendx(receiver..'||'..msg.from.phone..'||'..msg.text )
  reqclient:send(receiver..'||'..msg.from.phone..'||'..msg.text) -- send a synchronization request
  local message = reqclient:recv()   -- wait for synchronization reply
  if message ~= nil then
        receiver, phone, resp = message:match("([^|]+)|([^|]+)|([^|]+)")
        printf ("Received<< receiver:%s,phone:%s,msg:%s \n", receiver, phone, resp)
        _send_msg(receiver, resp)
  end
   --_send_msg(receiver, resp)
end
-- Where magic happens
function olddo_action(msg)
  local receiver = get_receiver(msg)
  local text = msg.text
  if msg.text == nil then
     -- Not a text message, make text the same as what tg shows so
     -- we can match on it. The plugin is resposible for handling
     text = '['..msg.media.type..']'
  end

  msg.text = do_lex(msg, text)

  for name, desc in pairs(plugins) do
    -- print("Trying module", name)
    for k, pattern in pairs(desc.patterns) do
      -- print("Trying", text, "against", pattern)
      matches = { string.match(text, pattern) }
      if matches[1] then
        mark_read(get_receiver(msg), ok_cb, false)
        print("  matches", pattern)
        if desc.run ~= nil then
          -- If plugin is for privileged user
          if desc.privileged and not is_sudo(msg) then
            local text = 'This plugin requires privileged user'
            send_msg(receiver, text, ok_cb, false)
          else 
            result = desc.run(msg, matches)
            -- print("  sending", result)
            if (result) then
              result = do_lex(msg, result)
              _send_msg(receiver, result)
            end
          end
        end
      end
    end
  end
end
-- function that receives messages from ussd app
co = coroutine.create(
   function ()
      while true do
         local message = subscriber:recv()
         if message ~= nil then
            receiver, phone, resp = message:match("([^|]+)|([^|]+)|([^|]+)")
            printf ("Received<< receiver:%s,phone:%s,msg:%s \n", receiver, phone, resp)
            _send_msg(receiver, resp)
         end
         sleep(1)
      end

   end
)
function get_sub()
      while true do
         print("waiting for message...")
         local message = subscriber:recv()
         if message ~= nil then
            receiver, phone, resp = message:match("([^|]+)|([^|]+)|([^|]+)")
            printf ("Received<< receiver:%s,phone:%s,msg:%s \n", receiver, phone, resp)
            _send_msg(receiver, resp)
         end
         sleep(1)
      end

   end
-- If text is longer than 4096 chars, send multiple msg.
-- https://core.telegram.org/method/messages.sendMessage
function _send_msg( destination, text)
  local msg_text_max = 4096
  local len = string.len(text)
  local iterations = math.ceil(len / msg_text_max)

  for i = 1, iterations, 1 do
    local inital_c = i * msg_text_max - msg_text_max
    local final_c = i * msg_text_max
    -- dont worry about if text length < msg_text_max
    local text_msg = string.sub(text,inital_c,final_c)
    send_msg(destination, text_msg, ok_cb, false)
  end
end

-- Save the content of _config to config.lua
function save_config( )
  serialize_to_file(_config, './data/config.lua')
  print ('saved config into ./data/config.lua')
end


function load_config( )
  local f = io.open('./data/config.lua', "r")
  -- If config.lua doesnt exists
  if not f then
    print ("Created new config file: data/config.lua")
    create_config()
  else
    f:close()
  end
  local config = loadfile ("./data/config.lua")()
  for v,user in pairs(config.sudo_users) do
    print("Allowed user: " .. user)
  end
  return config
end

-- Create a basic config.json file and saves it.
function create_config( )
  -- A simple config with basic plugins and ourserves as priviled user
  config = {
    enabled_plugins = {
      "9gag",
      "weather"
       },
    sudo_users = {our_id}  
  }
  serialize_to_file(config, './data/config.lua')
  print ('saved config into ./data/config.lua')
end

function on_our_id (id)
  our_id = id
end

function on_user_update (user, what)
  --vardump (user)
end

function on_chat_update (chat, what)
  --vardump (chat)
end

function on_secret_chat_update (schat, what)
  --vardump (schat)
end

function on_get_difference_end ()
end

-- Enable plugins in config.json
function load_plugins()
  for k, v in pairs(_config.enabled_plugins) do
    print("Loading plugin", v)
    t = loadfile("plugins/"..v..'.lua')()
    table.insert(plugins, t)
  end
end

-- Cron all the enabled plugins
function cron_plugins()

  for name, desc in pairs(plugins) do
    if desc.cron ~= nil then
      print(desc.description)
      desc.cron()
    end
  end

  -- Called again in 5 mins
  postpone (cron_plugins, false, 5*60.0)
end

-- Start and load values
our_id = 0
now = os.time()
--can_start_sub = true
