'use strict';

// notifier : reçoit les nouveaux produits et "envoie" une notification
// (ici un simple log, qui simule un email ou un message Slack)
const express = require('express');

const PORT = Number(process.env.PORT || 4000);
const app = express();
app.use(express.json());

app.get('/health', (req, res) => res.json({ status: 'UP' }));

app.post('/notify', (req, res) => {
  console.log(JSON.stringify({ level: 'info', service: 'notifier', msg: 'nouveau produit', product: req.body }));
  res.status(202).json({ received: true });
});

const server = app.listen(PORT, () => {
  console.log(JSON.stringify({ level: 'info', msg: 'notifier started', port: PORT }));
});

// PID 1 : arrêt propre sur docker stop
process.on('SIGTERM', () => server.close(() => process.exit(0)));
