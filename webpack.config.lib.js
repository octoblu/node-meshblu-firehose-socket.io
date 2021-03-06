var path              = require('path');
var webpack           = require('webpack');
module.exports = {
  devtool: 'cheap-eval',
  entry: [
    './src/firehose-socket-io.coffee'
  ],
  output: {
    libraryTarget: 'commonjs2',
    library: 'MeshbluFirehose',
    path: path.join(__dirname, 'dist'),
    filename: 'bundle.js'
  },
  module: {
    loaders: [
      {
        test: /\.coffee$/, loader: 'coffee-loader', include: /src/
      }
    ]
  },
  node: {
    dns: 'mock'
  },
  plugins: [
    new webpack.IgnorePlugin(/^(buffertools)$/), // unwanted "deeper" dependency
    new webpack.NoErrorsPlugin(),
    new webpack.DefinePlugin({
      'process.env': {
        'NODE_ENV': JSON.stringify('production')
      }
    }),
    new webpack.optimize.UglifyJsPlugin({
      compressor: {
        screw_ie8: true,
        warnings: false
      }
    })
  ]
};
