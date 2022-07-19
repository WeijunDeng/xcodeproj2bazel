require 'digest'

class KeyValueStore
    def self.get_key_value_store_in_container(container, key)
        unless key and key.size > 0
            raise "unexpected #{key}"
        end
        store = container[key]
        unless store
            store = {}
            container[key] = store
        end
        return store
    end

end