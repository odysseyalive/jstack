const express = require('express');
const app = express();
app.use(express.static('public'));
app.get('/', (req, res) => res.send('<h1>Node/MDX/Tailwind Template</h1><p>Edit public/index.html to customize.</p>'));
app.listen(4000, () => console.log('Server running on port 4000'));
