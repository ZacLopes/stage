/// Chave de identidade de uma cidade na tela "Onde você quer trabalhar?".
///
/// Revisão UX 28/07, achado P2-23. A tela pré-adiciona a cidade de residência
/// e precisa marcar ESSE card — e só ele — com "Onde você mora". Para isso
/// tem que reconhecer, no meio da lista, qual card é o que ela mesma semeou.
///
/// Comparar objeto não serve: o `OtherLocation` semeado nasce com `id: ''` e
/// vira outro objeto depois do save. Comparar só o nome da cidade também não:
/// "Campinas/SP" e "Campinas/RJ" são cidades diferentes. A chave é
/// cidade+UF, com a cidade em caixa baixa porque a mesma cidade chega
/// capitalizada de um lado e crua do outro (perfil × catálogo de busca).
String locationKey(String? city, String? state) =>
    '${(city ?? '').trim().toLowerCase()}|${(state ?? '').trim()}';
