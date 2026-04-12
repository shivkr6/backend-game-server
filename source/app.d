module app;

import vibe.core.core;
import vibe.core.concurrency;
import vibe.core.log;
import vibe.http.router : URLRouter;
import vibe.http.server;
import vibe.http.websockets : WebSocket, handleWebSockets;
import core.time;
import std.algorithm : remove;

struct ClientConnected { Tid tid; }
struct ClientDisconnected { Tid tid; }

void gameServerTask() nothrow
{
    Tid[] clients;
    try
    {
        while (true)
        {
            receive((string message) {
                logInfo("string message: %s", message);
                foreach (client; clients)
                {
                    client.send(message);
                }

            }, (ClientConnected client) {
                clients ~= client.tid;
                logInfo("new client appended: %s", clients);

            }, (ClientDisconnected client) {
                clients = clients.remove!(c => c == client.tid);
            });
        }
    }
    catch (Exception e)
    {
        logError("Game server task encountered an error: %s", e.msg);
    }
}

int main(string[] args)
{
    auto gameServer = runTask(&gameServerTask);

    auto router = new URLRouter;
    router.get("/ws", handleWebSockets((WebSocket socket) {
            handleWebSocketConnection(socket, gameServer.tid);
        }));

    auto settings = new HTTPServerSettings;
    settings.port = 8080;
    settings.bindAddresses = ["::1", "127.0.0.1"];

    listenHTTP(settings, router);
    return runApplication(&args);
}

void handleWebSocketConnection(scope WebSocket socket, Tid gameServer)
{
    gameServer.send(ClientConnected(thisTid));

    logInfo("Got new web socket connection.");
    while (socket.connected)
    {
        string data;
        if (socket.waitForData(10.msecs))
        {
            data = socket.receiveText();
            gameServer.send(data);
        }

        receiveTimeout(10.msecs, (string message) { socket.send(message); });
    }

    gameServer.send(ClientDisconnected(thisTid));
    logInfo("Client disconnected.");
}
