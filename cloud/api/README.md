# 椰子面试 Cloud API

This app powers the network side of coco-interview.

## Responsibilities

- issue ASR live-session credentials for the iOS app
- persist meetings, attachments, and related metadata
- run AI endpoints for titles, enhanced notes, and chat
- expose health and admin surfaces for development and debugging

## Local Development

```bash
npm install
npx prisma generate
npm run dev
```

Useful routes:

- `/`
- `/healthz`
- `/api/llm/status`
- `/api/asr/status`

## Build

```bash
npm run build
```

## Notes

- This service is designed to work with PostgreSQL through Prisma.
- It can be deployed on its own or paired with `cloud/asr-proxy` behind one public entrypoint.
- Public deployments should provide their own environment variables explicitly; this repo does not assume a production domain.
