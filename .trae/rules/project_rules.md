- 代码注释都是英文，且每行不超 80 字符
- 这个一个纯 dart 实现的 websocket 库，目的是为了简化 websocket 的使用
- 你基于官方的 [websocket](https://pub.dev/packages/web_socket) 实现了一个简单的库
- 特别注意要处理好断连后重连的情况. 我之前使用官方的库, 但是在断连后重连时, 会出现状态还是连接成功，但实际已经是断开状态的情况
- Api 设计的尽量轻量：
  connect: 连接 websocket 服务器
  disconnect: 断开 websocket 连接
  onStateChange: 监听 websocket 状态变化
    状态包括: 连接中, 已连接, 已断开
  send: 发送消息到服务器
  onReceive: 从服务器接收消息回响