#!/usr/bin/env node

const readline = require("readline");

const rl = readline.createInterface({
  input: process.stdin,
  crlfDelay: Infinity,
});

function write(message) {
  process.stdout.write(`${JSON.stringify(message)}\n`);
}

rl.on("line", (line) => {
  if (!line.trim()) {
    return;
  }

  const request = JSON.parse(line);
  switch (request.method) {
    case "initialize":
      write({ id: request.id, result: { name: "fixture", version: "1.0.0" } });
      break;
    case "provider.probe":
      write({
        id: request.id,
        result: {
          provider: request.params.provider,
          available: true,
          supportsTools: true,
          supportsTranscriptResume: true,
        },
      });
      break;
    case "session.create":
      write({
        id: request.id,
        result: {
          backendSessionId: `${request.params.sessionId}-backend`,
        },
      });
      break;
    case "session.message":
      write({
        id: request.id,
        result: {
          backendSessionId: `${request.params.sessionId}-backend`,
          resultText: `fixture reply: ${request.params.text}`,
          inputTokens: 2,
          outputTokens: 3,
          numTurns: 1,
          events: [
            { type: "toolCall", sessionId: request.params.sessionId, tool: "echo", input: "{\"message\":\"hi\"}" },
            { type: "toolResult", sessionId: request.params.sessionId, tool: "echo", output: "hi" },
            { type: "token", sessionId: request.params.sessionId, text: "fixture " },
            { type: "token", sessionId: request.params.sessionId, text: "reply " },
          ],
        },
      });
      break;
    case "session.resume":
    case "session.pause":
    case "session.fork":
      write({
        id: request.id,
        result: {
          backendSessionId: `${request.params.sessionId || request.params.childSessionId}-backend`,
        },
      });
      break;
    default:
      write({ id: request.id, error: { code: -32601, message: `Unknown method ${request.method}` } });
      break;
  }
});
