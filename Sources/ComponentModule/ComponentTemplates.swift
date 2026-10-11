import PlantUMLCore

public enum ComponentTemplates {
  public static let builtins: [DiagramTemplate] = [
    .init(
      name: "Client / Server", category: "Component", kind: "component",
      fragment: "component Client\ncomponent Server\nClient --> Server : HTTPS"),
    .init(
      name: "Microservices", category: "Component", kind: "component",
      fragment:
        "package Platform {\n component Orders\n component Payments\n}\nOrders --> Payments : API"),
    .init(
      name: "API Gateway", category: "Component", kind: "component",
      fragment:
        "component Client\ncomponent Gateway\ncomponent Service\nClient --> Gateway\nGateway --> Service"
    ),
    .init(
      name: "Service + Database", category: "Component", kind: "component",
      fragment: "component Service\ndatabase Store\nService --> Store : SQL"),
    .init(
      name: "Queue", category: "Component", kind: "component",
      fragment:
        "component Producer\ncomponent Broker\ncomponent Consumer\nProducer ..> Broker : publish\nBroker ..> Consumer : deliver"
    ),
    .init(
      name: "Multiple systems", category: "Component", kind: "component",
      fragment:
        "package Internal {\n component Backend\n}\ncloud External {\n component Provider\n}\nBackend --> Provider : integration"
    ),
  ]
}
