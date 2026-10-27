import Foundation

/// Новый порядок плейлистов после перетаскивания одного на место другого.
///
/// Правило то же, что раньше: элемент удаляется со своего места и вставляется
/// на позицию целевого. Возвращает nil, если перемещения нет.
enum PlaylistOrdering {

    static func moved(_ ids: [UUID], moving id: UUID, onto targetID: UUID) -> [UUID]? {
        guard let from = ids.firstIndex(of: id),
              let to = ids.firstIndex(of: targetID),
              from != to else { return nil }
        var result = ids
        let item = result.remove(at: from)
        result.insert(item, at: to)
        return result
    }
}
