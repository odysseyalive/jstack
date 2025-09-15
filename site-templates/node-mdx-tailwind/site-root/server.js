const express = require('express');
const app = express();
const PORT = process.env.PORT || 4000;

app.use(express.static('public'));
app.get('/', (req, res) => res.send('<h1>Node/MDX/Tailwind Template</h1><p>Edit public/index.html to customize.</p>'));
app.listen(PORT, () => console.log(`Server running on port ${PORT}`));
