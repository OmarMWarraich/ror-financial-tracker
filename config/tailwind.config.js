const shadcn = require('./shadcn.tailwind.js')

module.exports = {
  ...shadcn,
  plugins: [
    ...shadcn.plugins.filter(plugin => plugin !== require('@tailwindcss/forms')),
    require('@tailwindcss/forms')({ strategy: 'class' })
  ]
}
