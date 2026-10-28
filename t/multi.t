use Test::Nginx::Socket::Lua 'no_plan';

log_level('info');
no_long_string();
no_shuffle();

$ENV{TEST_NGINX_DUBBO_SOCK} ||= html_dir() . "/dubbo.sock";

# a stub dubbo backend: answers every request with status 200 and body "dubbo ok"
my $stub = <<'_EOC_';
local bit = require("bit")

local function be32(s, i)
    local a, b, c, d = s:byte(i, i + 3)
    return ((a * 256 + b) * 256 + c) * 256 + d
end

local function u32(n)
    return string.char(bit.band(bit.rshift(n, 24), 0xff), bit.band(bit.rshift(n, 16), 0xff),
                       bit.band(bit.rshift(n, 8), 0xff), bit.band(n, 0xff))
end

local function str(s)
    return string.char(#s) .. s
end

local function bin(s)
    return string.char(0x20 + #s) .. s
end

local sock = assert(ngx.req.socket(true))
while true do
    local hdr = sock:receive(16)
    if not hdr then
        return
    end

    local len = be32(hdr, 13)
    if len > 0 and not sock:receive(len) then
        return
    end

    local flag, reqid = hdr:byte(3), hdr:sub(5, 12)
    local typ, payload
    if bit.band(flag, 0x20) ~= 0 then
        typ, payload = 0x22, "N"
    else
        typ = 0x02
        payload = "\x91H" .. str("status") .. str("200")
                  .. str("body") .. bin("dubbo ok") .. "Z"
    end

    sock:send("\xda\xbb" .. string.char(typ, 20) .. reqid .. u32(#payload) .. payload)
end
_EOC_

add_block_preprocessor(sub {
    my ($block) = @_;

    # a slow shutdown can leave the socket behind
    unlink $ENV{TEST_NGINX_DUBBO_SOCK};
    my $listen_unix = '';
    if (($block->http_config // '') =~ /TEST_NGINX_DUBBO_SOCK/) {
        $listen_unix = "listen unix:$ENV{TEST_NGINX_DUBBO_SOCK};";
    }

    my $main_config = $block->main_config // '';
    $main_config .= <<_EOC_;
stream {
    server {
        listen 1986;
        $listen_unix
        content_by_lua_block {
$stub
        }
    }
}
_EOC_
    $block->set_value("main_config", $main_config);

    if (!$block->request) {
        $block->set_value("request", "GET /t");
    }

    if (!$block->no_error_log && !$block->error_log) {
        $block->set_value("no_error_log", "[error]\n[alert]");
    }
});

run_tests();

__DATA__

=== TEST 1: multiplexed dubbo request
--- http_config
upstream dubbo_backend {
    server 127.0.0.1:1986;
    multi 4;
}
--- config
location /t {
    dubbo_pass org.apache.dubbo.Demo 1.0.0 hello dubbo_backend;
}
--- response_body chomp
dubbo ok
--- error_log
multi: connect new to backend



=== TEST 2: later requests reuse the multi connection
--- http_config
upstream dubbo_backend {
    server 127.0.0.1:1986;
    multi 1;
}
--- config
location /dubbo {
    dubbo_pass org.apache.dubbo.Demo 1.0.0 hello dubbo_backend;
}
location /t {
    content_by_lua_block {
        for i = 1, 2 do
            local res = ngx.location.capture("/dubbo")
            ngx.say(res.status, " ", res.body)
        end
    }
}
--- response_body
200 dubbo ok
200 dubbo ok
--- error_log
multi: connect reuse



=== TEST 3: requests on a connection that is still connecting wait for it
--- http_config
upstream dubbo_backend {
    server 127.0.0.1:1986;
    multi 1;
}
--- config
location /dubbo {
    dubbo_pass org.apache.dubbo.Demo 1.0.0 hello dubbo_backend;
}
location /t {
    content_by_lua_block {
        -- both start before the connect completes, so the second one
        -- lands on the connection the first one is still opening
        local r1, r2 = ngx.location.capture_multi({ {"/dubbo"}, {"/dubbo"} })
        ngx.say(r1.status, " ", r1.body)
        ngx.say(r2.status, " ", r2.body)
    }
}
--- response_body
200 dubbo ok
200 dubbo ok
--- error_log
multi: connect reuse unfinished



=== TEST 4: a new connection that connects immediately
unix sockets connect synchronously
--- http_config
upstream dubbo_backend {
    server unix:$TEST_NGINX_DUBBO_SOCK;
    multi 4;
}
--- config
location /t {
    dubbo_pass org.apache.dubbo.Demo 1.0.0 hello dubbo_backend;
}
--- response_body chomp
dubbo ok
--- error_log
multi: connect new to backend immediately



=== TEST 5: multi upstream used by a handler that can not multiplex
--- http_config
upstream backend {
    server 127.0.0.1:1986;
    multi 4;
}
--- config
location /t {
    proxy_pass http://backend;
}
--- error_code: 500
--- error_log
multi: upstream configured multi, but handler does not support it



=== TEST 6: dubbo_pass to an upstream without multi
--- http_config
upstream dubbo_backend {
    server 127.0.0.1:1986;
}
--- config
location /t {
    dubbo_pass org.apache.dubbo.Demo 1.0.0 hello dubbo_backend;
}
--- error_code: 500
--- error_log
multi: need multi, but upstream does not support it
