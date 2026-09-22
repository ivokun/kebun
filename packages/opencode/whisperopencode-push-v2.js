import { checkin } from "./checkin.js"
import { record } from "./event.js"
import { publish } from "./relay.js"
import { load, save } from "./state.js"

// @whisperopencode/push 0.3.0 consumes V1's { type, properties } events.
// Translate only the events it understands from V2's { type, data } stream.
const legacyEvent = (event) => {
  const data = event.data ?? {}

  switch (event.type) {
    case "session.created":
      return {
        type: event.type,
        properties: {
          info: {
            id: data.sessionID,
            parentID: data.parentID,
          },
        },
      }
    case "session.deleted":
      return {
        type: event.type,
        properties: { info: { id: data.sessionID } },
      }
    case "session.execution.succeeded":
    case "session.execution.interrupted":
      return {
        type: "session.idle",
        properties: { sessionID: data.sessionID },
      }
    case "session.execution.failed":
      return {
        type: "session.error",
        properties: { sessionID: data.sessionID },
      }
    case "form.created":
      return {
        type: "question.asked",
        properties: {
          id: data.form?.id,
          sessionID: data.form?.sessionID,
        },
      }
    default:
      return { type: event.type, properties: data }
  }
}

export default {
  id: "whisperopencode-push",

  setup(ctx) {
    const controller = new AbortController()
    const boot = load()
      .then(async (data) => {
        if (data.mode !== "relay" || !data.relay) return
        await checkin(data, "plugin")
      })
      .catch(() => undefined)

    let run = Promise.resolve()
    const subscription = (async () => {
      for await (const event of ctx.event.subscribe({ signal: controller.signal })) {
        run = run
          .then(async () => {
            await boot
            const data = await load()
            const item = await record(data, legacyEvent(event))

            if (item && data.mode === "relay" && data.relay) {
              const relay = data.relay
              await publish(data, item)
                .then((response) => {
                  data.relay = {
                    ...relay,
                    checked: Date.now(),
                    result: response.suppressed ? "suppressed" : "accepted",
                    reason: response.reason,
                    delivery: response.deliveries?.[0]?.delivery_id,
                    err: undefined,
                  }
                })
                .catch((error) => {
                  data.relay = {
                    ...relay,
                    checked: Date.now(),
                    result: "failed",
                    err: error instanceof Error ? error.message : String(error),
                  }
                })
            }

            await save(data)
          })
          .catch(() => undefined)
      }
    })().catch(() => undefined)

    return async () => {
      controller.abort()
      await Promise.allSettled([subscription, run])
    }
  },
}
